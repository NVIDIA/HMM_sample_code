#if 0
  set -ex
  nvc++ -std=c++20 -stdpar=gpu -gpu=nomanaged -o file_after $0
  ./file_after 10
  exit 0
#endif
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
#include <algorithm>
#include <execution>
#include <fcntl.h>
#include <fstream>
#include <functional>
#include <iostream>
#include <ranges>
#include <span>
#include <stdio.h>
#include <sys/mman.h>
#include <vector>

void use_data(std::span<char>);

void sortfile(int fd, int N) {
  char* buffer = (char*)mmap(NULL, N, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (buffer == nullptr) {
    std::cerr << "Failed to mmap file!" << std::endl;
    abort();
  }
  std::sort(std::execution::par, buffer, buffer + N, std::greater{});
  use_data(std::span{buffer, N});
  munmap(buffer, N);
}

void use_data(std::span<char> data) {
  for (auto c : data) std::cout << c << std::endl;
}

int main(int argc, char* argv[]) {
  if (argc != 2) {
    std::cerr << "ERROR: missing length argument" << std::endl;
    std::cerr << "Usage: " << argv[0] << " <file bytes> " << std::endl;
    abort();
  }
  std::size_t N = std::stoll(argv[1]);

  // Generate a file with n elements
  char const* fname = "file_after.txt";
  {
    std::cout << "Generating file with " << N << " bytes..." << std::endl;
    std::ofstream out(fname);
    if (!out) {
      std::cerr << "File open failed!" << std::endl;
      abort();
    }
    std::vector<unsigned char> buffer(N);
    std::for_each_n(std::execution::par, std::views::iota(0).begin(), N,
                    [&](int i) { buffer[i] = (unsigned char)'0' + (unsigned char)i; });
    out.write((const char*)buffer.data(), N);
    out.close();
  }

  int fd = open(fname, O_RDWR);
  if (fd == -1) {
    std::cerr << "Failed to read file" << std::endl;
    abort();
  }
  sortfile(fd, N);
  return 0;
}
