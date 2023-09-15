#include <iostream>
#include <fstream>
#include <random>


int days_in_month(int month,int year) {
  int days_in_month = 31;
  if (month == 2) {
    if (year % 4 == 0) {
      days_in_month = 29;
    } else {
      days_in_month = 28;
    }
  } else if (month == 4 || month == 6 || month == 9 || month == 11) {
    days_in_month = 30;
  }
  return days_in_month;
}


int main(int argc, char** argv) {
  const int start_year(1981);
  const int end_year(1982);
  const int input_grid_height = 721;
  const int input_grid_width = 1440;
  for (int year(start_year); year <= end_year; year++) {
    for (int month(1); month <= 12; month++) {
      char buf[3];
      sprintf(buf,"%02i",month);
      std::string filename = "binary_1hr_all/e5.accumulated_tp_1h." + std::to_string(year) + buf + ".bin";
      std::cout << "writing: " << filename << std::endl;
      // now create the random numbers
      std::ofstream outfile(filename, std::ios::binary);
      // Create a random number generator.
      std::default_random_engine generator;
      std::uniform_real_distribution<float> distribution(0.0, 1.0);
      // create a random value for every point in the grid (721 * 1440)
      for (int i = 0; i < days_in_month(month,year); i++) {
        for (int h = 0; h < 24; h++) {
          for (int j = 0; j < input_grid_height * input_grid_width; j++) {
            float ran = distribution(generator) * float((12*12-(h-12)*(h-12)) * month);
            outfile.write((char*)&ran, sizeof(float));
          }
        }
      }
      outfile.close();
    }
  }
  return 0;
}

