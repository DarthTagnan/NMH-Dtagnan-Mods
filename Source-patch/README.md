# NMH Dtagnan Mods - Custom DXVK Source

The DXVK binaries included with NMH Dtagnan Mods 1.1.1 are based on
the upstream DXVK project with a custom built-in profile for
No More Heroes.

## Upstream

Project:
https://github.com/doitsujin/dxvk

Base commit:

    60193094

## Dtagnan Modification

Custom commit:

    fd3612f4

Modified file:

    src/util/config/config.cpp

The custom profile is automatically applied to:

    nmh.exe

It enables the following DXVK options:

    dxgi.maxFrameLatency = 1
    dxvk.numCompilerThreads = 4
    dxvk.enablePresentTiming = True
    dxvk.enableImplicitResolves = True

The complete source modification is provided in:

    nmh-dxvk.patch

## Reproducing the Source

Clone upstream DXVK:

    git clone https://github.com/doitsujin/dxvk.git
    cd dxvk

Checkout the exact upstream revision used by NMH Dtagnan Mods 1.1.1:

    git checkout 60193094

Apply the NMH patch:

    git am /path/to/nmh-dxvk.patch

The resulting source tree contains the custom DXVK modifications
used by NMH Dtagnan Mods 1.1.

## License

DXVK remains subject to its upstream license.
See the upstream DXVK project for its license and copyright notices.
