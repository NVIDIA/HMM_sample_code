# ERA5 Total Precipitation Data Aggregation
The sample code here demonstrates how to aggregate data and generate few statistics for total precpitation from the ERA5 weather re-analysis dataset. 

## Data Download
The input data for this application can be downloaded from the [this](https://cds.climate.copernicus.eu/cdsapp#!/dataset/reanalysis-era5-single-levels?tab=form) link. The ERA5 dataset consists of hourly estimates of several atmospheric variables at a latitude and longitude resolution of 0.25°. The 0.25° resolution results in 721x1440 distinct locations on earth. In the ERA5 dataset total precipitation data for each month is stored in a separate file in NetCDF format. For our application we pre-processed the files from NetCDF to binary format consisting of the raw floating point values. You can use the provided python script [`era5_preicp_nc_to_bin.py`](./era5_preicp_nc_to_bin.py) to convert data from NetCDF to binary format. For our test we used 40 years of “Total precipitation” data from 1981-2020, which sum to 480 input files aggregating to ~1.3 TB total input data size.

## Build and Run Instructions
Use the provided `Makefile` to compile the application, which will produce binary named `weather_app`. The binary takes 3 commandline arguments.

```
./weather_app StartYear EndYear /PATH\_TO\_BINARY\_FILES/
```

The application uses HMM to mmap the input binary files and using CUDA computes the total precipitation for each hour for all the days in a year for the input year range. It outputs a csv file (`processed_log.csv`) with average monthly precipitation and average per-hour precipitation for each month of the year. The raw accumulated total precipitation for each hour of the year is also saved to file in binary format.
