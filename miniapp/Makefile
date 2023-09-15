NVCC ?= nvcc

all: weather_app

weather_app: weather_app.cu
	$(NVCC) $^ -o $@ -std=c++11 -gencode arch=compute_80,code=sm_80 \
                              -gencode arch=compute_90,code=sm_90 \
                              -gencode arch=compute_75,code=sm_75 \
                              -gencode arch=compute_90,code=compute_90

clean:
	$(RM) weather_app
