CUDA 12.2 Heterogeneous Memory Management (HMM) demos
===

This repository contains the HMM demos of the [Simplifying GPU Application Development with HMM (Heterogeneous Memory Management)] blogpost.

The HMM requirements are described in the [CUDA 12.2 Release Notes].
The demos require a system with ATS or HMM enabled; this can be verifyied by querying the Addressing Mode using `nvidia-smi`:

```shell
$ nvidia-smi -q | grep Addressing

Addressing Mode                       : HMM
```

The demos are available in the [`src/`](./src) directory. On systems with docker installed, they can be run as follows:

```shell
./ci/run
```

# License

See [LICENSE](./LICENSE).

[Simplifying GPU Application Development with HMM (Heterogeneous Memory Management)]: link.
[CUDA 12.2 Release Notes]: https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/index.html#general-cuda
