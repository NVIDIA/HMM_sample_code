#if 0
  set -ex
  nvc++ -std=c++20 -stdpar=gpu -gpu=nomanaged -o atomic_flag $0
  ./atomic_flag
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
#include <atomic>
#include <execution>
#include <iostream>
#include <thread>

int main() {

  std::atomic<int> flag = 0;
  int message = 0;

  // Start a new thread that launches a GPU kernel
  auto t = std::jthread([&] {
    std::for_each_n(std::execution::par, &message, 1, [&](int& m) {
      m = 42;
      flag.store(1);
    });
  });

  // Wait on the flag
  while (flag.load() == 0)
    ;
  // Read the message
  std::cout << "CPU read message sent by GPU thread: " << message << std::endl;

  return 0;
}
