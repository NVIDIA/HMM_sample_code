NVCC ?= nvcc

all: weather_app create_random_data

weather_app: weather_app.cu
	$(NVCC) $^ -o $@ -std=c++11 -gencode arch=compute_80,code=sm_80 \
                              -gencode arch=compute_90,code=sm_90 \
                              -gencode arch=compute_90,code=compute_90

write_random_data: write_random_data.cc
	$(CXX) $^ -o $@ -O2 -Wall

clean:
	$(RM) weather_app write_random_data
