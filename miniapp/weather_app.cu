/*
 * SPDX-FileCopyrightText: Copyright (c) 2023 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

#include <cassert>
#include <cerrno>
#include <cstdint>
#include <cub/cub.cuh>
#include <cuda_runtime_api.h>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <numeric>
#include <string>
#include <sys/mman.h>
#include <unistd.h>
#include <vector>

#define CUDA_CHECK(cmd)                                                                                      \
  { cudaError_t err = cmd; \
  if (err != cudaSuccess) {                                                                                  \
    std::cout << "CUDA error at " << __LINE__ << " " << cudaGetErrorString(err) << std::endl;                \
    return -1;}                                                                                               \
  }

__constant__ size_t month_day_boundary[13] = {0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366};

__inline__ __device__ int get_month_from_day_of_year(int day_of_year) {
  const int total_months = 12;

  int month = total_months / 2;
  int upper_month = total_months;
  int lower_month = 0;

  // binary search in array
  while (lower_month <= upper_month) {
    if (day_of_year >= month_day_boundary[month])
      lower_month = month + 1;
    else if (day_of_year < month_day_boundary[month])
      upper_month = month - 1;
    month = int((upper_month + lower_month) / 2);
  }
  return month; // this is 0 based
}

__global__ void construct_yearly_histogram(float *input_data, int start_year, int end_year,
                                           size_t input_grid_height, size_t input_grid_width,
                                           size_t aligned_month_file_map_offset, float *histogram_data) {
  // end year is included
  const size_t hours_per_day = 24; // assumed 24 hr data
  const size_t days_per_leap_year = 366;
  const size_t months_per_year = 12;

  // sum will accumulate in register for the full grid
  size_t grid_pitch = input_grid_height * input_grid_width;
  size_t day_grid_pitch = hours_per_day * grid_pitch;

  // output mapping
  // total 366 * 24 * 721 * 1440 active threads
  size_t linear_day_hr_loc_idx = (size_t)blockDim.x * blockIdx.x + threadIdx.x;

  size_t max_active_threads = (days_per_leap_year * (int64_t)day_grid_pitch);

  size_t day_of_year = linear_day_hr_loc_idx / day_grid_pitch; // this is 0-based
  size_t hour_of_day = (linear_day_hr_loc_idx - (day_of_year * day_grid_pitch)) / grid_pitch;
  size_t grid_linearized_idx =
      linear_day_hr_loc_idx - (day_of_year * day_grid_pitch) - (hour_of_day * grid_pitch);

  size_t grid_y = grid_linearized_idx / input_grid_width;
  size_t grid_x = grid_linearized_idx % input_grid_width;

  // month is required as each file is mapped at a separate offset - for page boundary alignment
  size_t month = (size_t)get_month_from_day_of_year((int)day_of_year);

  if (linear_day_hr_loc_idx < max_active_threads) {
    float accum_sum = 0.0f;

    for (int i = 0; i <= (end_year - start_year); i++) {
      int year = i + start_year;

      size_t access_index = (((size_t)i * months_per_year + month) * aligned_month_file_map_offset) +
                            ((day_of_year - month_day_boundary[month]) * day_grid_pitch) +
                            (hour_of_day * grid_pitch) + grid_y * input_grid_width + grid_x;
      // leap year adjustment for feb
      if (day_of_year == 59) {
        if ((year % 4) == 0) {
          // leap year - read away
          accum_sum += input_data[access_index];
        }
      } else {
        accum_sum += input_data[access_index];
      }
    }
    // write out
    histogram_data[linear_day_hr_loc_idx] = accum_sum;
  }
}

int main(int argc, char *argv[]) {

  // hard coded constants for ERA5
  const int hours_per_day = 24; // assumed 24 hr data
  const int days_per_leap_year = 366;
  const int max_days_per_month = 31;
  const int months_per_year = 12;
  const int input_grid_height = 721;
  const int input_grid_width = 1440;
  int start_year = std::atoi(argv[1]);
  int end_year = std::atoi(argv[2]);
  std::string file_path = std::string(argv[3]);

  const int num_years = end_year - start_year + 1;

  size_t max_file_size =
      sizeof(float) * max_days_per_month * hours_per_day * input_grid_height * input_grid_width;

  size_t TWO_MB = 2 * 1024 * 1024;
  size_t max_aligned_file_pages = (max_file_size + TWO_MB - 1) / TWO_MB;
  size_t max_aligned_file_size = max_aligned_file_pages * TWO_MB;

  std::cout << "aligned size: " << max_aligned_file_size << std::endl;

  std::vector<size_t> file_sizes;
  std::vector<int> open_fds;

  // 2 MB aligned VA range to allocate
  size_t va_alloc_size = sizeof(float) * num_years * months_per_year * max_aligned_file_size;

  void *va_alloc = mmap(nullptr, va_alloc_size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);

  void *running_address = va_alloc;

  std::string file_path_base = file_path;

  for (int y = start_year; y <= end_year; y++) {
    for (int k = 1; k <= months_per_year; k++) {
      char filestr_buf[10];
      sprintf(filestr_buf, "%d%02d.bin", y, k);
      std::string filename = file_path_base + "e5.accumulated_tp_1h." + std::string(filestr_buf);
      std::cout << "mapping: " << filename << std::endl;

      std::ifstream fstreamInput(filename, std::ios::binary);
      fstreamInput.seekg(0, std::ios::end);
      size_t fileByteSize = fstreamInput.tellg();
      fstreamInput.close();

      int fd = open(filename.c_str(), O_RDONLY, 0);
      if (fd == -1) {
        std::cout << "Error opening input file: " << filename << std::endl;
        return -1;
      }

      char *mapped_addr = NULL;
      // probably need 2 MB pages for perf
      mapped_addr =
          (char *)mmap((void *)running_address, fileByteSize, PROT_READ, MAP_PRIVATE | MAP_FIXED, fd, 0);

      if (mapped_addr == MAP_FAILED) {
        close(fd);
        std::cout << "Error mapping input file: " << filename << std::endl;
        return -2;
      }

      assert(mapped_addr == (char *)running_address);
      running_address = (void *)((char *)running_address + max_aligned_file_size);

      file_sizes.push_back(fileByteSize);
      open_fds.push_back(fd);
    }
  }

  // launch kernel and feed in pointer and values
  size_t hist_bins = (size_t)days_per_leap_year * hours_per_day * input_grid_height * input_grid_width;
  size_t histogram_alloc_size = hist_bins * sizeof(float);
  float *histogram_data = NULL;
  CUDA_CHECK(cudaMalloc((void **)&histogram_data, histogram_alloc_size));
  CUDA_CHECK(cudaMemset(histogram_data, 0, histogram_alloc_size));

  cudaEvent_t start_event, stop_event;
  CUDA_CHECK(cudaEventCreate(&start_event));
  CUDA_CHECK(cudaEventCreate(&stop_event));

  dim3 block(1024, 1, 1);
  dim3 grid(1, 1, 1);

  grid.x = (hist_bins + block.x - 1) / block.x;

  CUDA_CHECK(cudaEventRecord(start_event));
  construct_yearly_histogram<<<grid, block, 0, NULL>>>(
      reinterpret_cast<float *>(va_alloc), start_year, end_year, (size_t)input_grid_height,
      (size_t)input_grid_width, max_aligned_file_size / sizeof(float), histogram_data);

  CUDA_CHECK(cudaGetLastError()); // for catching errors from launch
  CUDA_CHECK(cudaEventRecord(stop_event));
  CUDA_CHECK(cudaEventSynchronize(stop_event));

  float time_ms = 0.0f;
  CUDA_CHECK(cudaEventElapsedTime(&time_ms, start_event, stop_event));
  std::cout << "kernel time: " << time_ms << " ms" << std::endl;

  CUDA_CHECK(cudaDeviceSynchronize()); // to start reading output histogram on host

  size_t month_day_boundary[13] = {0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366};
  FILE *fp_log = fopen("processed_log.csv", "w");
  fprintf(fp_log, "Month,Total Precipitation (m)\n");
  std::vector<std::vector<float>> hourly_sum_per_day;

  for (int m = 0; m < months_per_year; m++) {
    size_t start_index = month_day_boundary[m] * hours_per_day * input_grid_height * input_grid_width;
    float local_sum = 0.0f;
    for (int d = 0; d < (month_day_boundary[m + 1] - month_day_boundary[m]); d++) {
      std::vector<float> hour_sum(24);
      for (int h = 0; h < hours_per_day; h++) {
        float month_sum[16] = {0.0f};
        void *d_temp_storage = NULL;
        size_t temp_storage_bytes = 0;
        size_t num_items = (input_grid_height / 2) * input_grid_width;
        size_t strided_hourly_idx = start_index + (d * hours_per_day * input_grid_height * input_grid_width) +
                                    (h * input_grid_height * input_grid_width);
        float *array_start = &(histogram_data[strided_hourly_idx]);
        cub::DeviceReduce::Sum(d_temp_storage, temp_storage_bytes, array_start, month_sum, num_items);

        d_temp_storage = malloc(temp_storage_bytes); // use HMM B-)
        cub::DeviceReduce::Sum(d_temp_storage, temp_storage_bytes, array_start, month_sum, num_items);
        cudaDeviceSynchronize();

        free(d_temp_storage);
        hour_sum[h] = month_sum[0];
      }
      hourly_sum_per_day.push_back(hour_sum);
      local_sum += std::accumulate(hour_sum.begin(), hour_sum.end(), 0.0f);
    }
    std::cout << "Month: " << (m + 1) << " Total Precip: " << local_sum << " m" << std::endl;
    fprintf(fp_log, "%d,%f\n", m + 1, local_sum);
  }

  // get per hour total rainfall for each month
  fprintf(fp_log, "Hourly average per-month\n");
  fprintf(fp_log, "Month,Hour,Total Precipitation (m)\n");
  for (int m = 0; m < months_per_year; m++) {
    for (int h = 0; h < hours_per_day; h++) {
      float hour_sum = 0.0f;
      for (int d = 0; d < (month_day_boundary[m + 1] - month_day_boundary[m]); d++) {
        hour_sum += hourly_sum_per_day[month_day_boundary[m] + d][h];
      }
      std::cout << "m: " << m + 1 << " h: " << h + 1 << " hour_sum: " << hour_sum << std::endl;
      fprintf(fp_log, "%d,%d,%f\n", m + 1, h + 1, hour_sum);
    }
    std::cout << std::endl;
  }
  fclose(fp_log);

  FILE *fp_out = fopen("yearly_aggregates.bin", "wb");
  fwrite(histogram_data, sizeof(float), hist_bins, fp_out);
  fflush(0);
  fclose(fp_out);

  CUDA_CHECK(cudaEventDestroy(start_event));
  CUDA_CHECK(cudaEventDestroy(stop_event));

  CUDA_CHECK(cudaFree(histogram_data));

  void *unmap_address = va_alloc;
  for (int k = 1; k < argc; k++) {
    int unmap_return = munmap(unmap_address, file_sizes[k - 1]); // unmap all address
    if (unmap_return != 0) {
      std::cout << "Error unmapping VA alloc range: " << strerror(errno) << std::endl;
    }
    close(open_fds[k - 1]);
    unmap_address = (void *)((char *)unmap_address + max_aligned_file_size);
  }

  int unmap_return = munmap(va_alloc, va_alloc_size); // unmap all address
  if (unmap_return != 0) { std::cout << "Error unmapping VA alloc range: " << strerror(errno) << std::endl; }

  return 0;
}
