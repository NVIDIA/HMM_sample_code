#if 0
  set -ex
  nvc++ -std=c++20 -stdpar=gpu -gpu=nomanaged -o ticket_lock $0
  ./ticket_lock
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
#include <ranges>
#include <thread>

struct ticket_lock {
  std::atomic<uint32_t> ticket = 0;
  std::atomic<uint32_t> lock = 0;

  struct guard_t {
    ticket_lock* p;
    ~guard_t() { p->lock.fetch_add(1, std::memory_order_release); }
  };

  guard_t guard() {
    uint32_t t = ticket.fetch_add(1, std::memory_order_relaxed);
    while (lock.load(std::memory_order_acquire) != t)
      ;
    return {this};
  }
};

int main() {
  ticket_lock lock;
  int message = 0;

  int cpu_threads = 64;
  int gpu_threads = 4096;

  {
    // Start a new thread that launches a GPU kernel
    auto t = std::jthread([&] {
      std::for_each_n(std::execution::par, std::views::iota(0).begin(), gpu_threads, [&](int) {
        auto g = lock.guard();
        message += 1;
      });
    });

    // Start cpu threads
    std::vector<std::jthread> threads;
    threads.reserve(cpu_threads);
    for (int i = 0; i < cpu_threads; ++i) {
      threads.emplace_back([&] {
        auto g = lock.guard();
        message += 1;
      });
    }
  } // All threads complete here

  // Read the message
  int should = cpu_threads + gpu_threads;
  if (message != should) {
    std::cerr << "FAILED: message = " << message << " != " << should << " threads" << std::endl;
    return 1;
  }
  std::cerr << "SUCESS: message = " << message << " == " << should << " threads" << std::endl;

  return 0;
}
