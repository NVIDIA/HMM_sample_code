# SPDX-FileCopyrightText: Copyright (c) 2023 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: MIT
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

import netCDF4 as nc
import numpy as np
from datetime import datetime, timedelta
from dateutil.relativedelta import relativedelta
from tqdm import tqdm

start_y = 1981
end_y = 2020

for y in range(end_y - start_y + 1):
  start_date = datetime(year=start_y+y, month=1, day=1)
  end_date = datetime(year=start_y+y, month=12, day=1)
  n_months = relativedelta(end_date, start_date).months + 1

  dates = [start_date + relativedelta(months=x) for x in range(n_months)]

  for date in tqdm(dates):
      file_prefix = date.strftime('e5.accumulated_tp_1h.%Y%m')
      input_filename = f"./raw_1hr_all/{file_prefix}.nc"
      output_filename = f"./binary_1hr_all/{file_prefix}.bin"
      print(f"Reading {input_filename} and outputting to {output_filename}")
    
      ds = nc.Dataset(input_filename, "r", format="NETCDF4")
      precip = np.asarray(ds["tp"])
      precip.tofile(output_filename)

