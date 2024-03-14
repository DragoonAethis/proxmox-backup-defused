Defused Proxmox Backup Client
*****************************

This is a slightly patched up version of proxmox-backup-client 3.x that:

- Does not depend on FUSE 3 at all (and cannot mount archives)
- Does not depend on system-provided libxcrypt and OpenSSL

This allows building and running PBS Client 3.x on Ubuntu 18.04 and other,
slightly older distros than what's officially supported. (For reference,
official Client 1.x runs on Ubuntu 20.04 and Debian 10.)

To run these binaries: ``apt-get install -y acl libuuid1 libattr1``

To build them, install deps above and::

    apt-get install -y build-essential clang-10 git libacl1-dev uuid-dev curl
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile=minimal
    source "$HOME/.cargo/env"
    cargo build \
        --no-default-features \
        --package proxmox-backup-client \
        --bin proxmox-backup-client \
        --package pxar-bin \
        --bin pxar \
        --release

Your binaries will be in ``target/release/{proxmox-backup-client,pxar}``.

Note that this repo references upstream git repos for some crates, which
can break over time. You might have to rebase or fix something before
a new build starts working here. The build throws a lot of ``unused``
warnings too, which are benign.

Known good ``proxmox.git`` commit: ``c67a13f1d7233c5621e717eb9a4222bff870e15a``

This is just a transitional package to safely get me off some older OSes.
The original README follows.


Build & Release Notes
*********************

``rustup`` Toolchain
====================

We normally want to build with the ``rustc`` Debian package. To do that
you can set the following ``rustup`` configuration:

    # rustup toolchain link system /usr
    # rustup default system


Versioning of proxmox helper crates
===================================

To use current git master code of the proxmox* helper crates, add::

   git = "git://git.proxmox.com/git/proxmox"

or::

   path = "../proxmox/proxmox"

to the proxmox dependency, and update the version to reflect the current,
pre-release version number (e.g., "0.1.1-dev.1" instead of "0.1.0").


Local cargo config
==================

This repository ships with a ``.cargo/config`` that replaces the crates.io
registry with packaged crates located in ``/usr/share/cargo/registry``.

A similar config is also applied building with dh_cargo. Cargo.lock needs to be
deleted when switching between packaged crates and crates.io, since the
checksums are not compatible.

To reference new dependencies (or updated versions) that are not yet packaged,
the dependency needs to point directly to a path or git source (e.g., see
example for proxmox crate above).


Build
=====
on Debian 12 Bookworm

Setup:
  1. # echo 'deb http://download.proxmox.com/debian/devel/ bookworm main' | sudo tee /etc/apt/sources.list.d/proxmox-devel.list
  2. # sudo wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
  3. # sudo apt update
  4. # sudo apt install devscripts debcargo clang
  5. # git clone git://git.proxmox.com/git/proxmox-backup.git
  6. # cd proxmox-backup; sudo mk-build-deps -ir

Note: 2. may be skipped if you already added the PVE or PBS package repository

You are now able to build using the Makefile or cargo itself, e.g.::

  # make deb
  # # or for a non-package build
  # cargo build --all --release

Design Notes
************

Here are some random thought about the software design (unless I find a better place).


Large chunk sizes
=================

It is important to notice that large chunk sizes are crucial for performance.
We have a multi-user system, where different people can do different operations
on a datastore at the same time, and most operation involves reading a series
of chunks.

So what is the maximal theoretical speed we can get when reading a series of
chunks? Reading a chunk sequence need the following steps:

- seek to the first chunk's start location
- read the chunk data
- seek to the next chunk's start location
- read the chunk data
- ...

Lets use the following disk performance metrics:

:AST: Average Seek Time (second)
:MRS: Maximum sequential Read Speed (bytes/second)
:ACS: Average Chunk Size (bytes)

The maximum performance you can get is::

  MAX(ACS) = ACS /(AST + ACS/MRS)

Please note that chunk data is likely to be sequential arranged on disk, but
this it is sort of a best case assumption.

For a typical rotational disk, we assume the following values::

  AST: 10ms
  MRS: 170MB/s

  MAX(4MB)  = 115.37 MB/s
  MAX(1MB)  =  61.85 MB/s;
  MAX(64KB) =   6.02 MB/s;
  MAX(4KB)  =   0.39 MB/s;
  MAX(1KB)  =   0.10 MB/s;

Modern SSD are much faster, lets assume the following::

  max IOPS: 20000 => AST = 0.00005
  MRS: 500Mb/s

  MAX(4MB)  = 474 MB/s
  MAX(1MB)  = 465 MB/s;
  MAX(64KB) = 354 MB/s;
  MAX(4KB)  =  67 MB/s;
  MAX(1KB)  =  18 MB/s;


Also, the average chunk directly relates to the number of chunks produced by
a backup::

  CHUNK_COUNT = BACKUP_SIZE / ACS

Here are some staticics from my developer worstation::

  Disk Usage:       65 GB
  Directories:   58971
  Files:        726314
  Files < 64KB: 617541

As you see, there are really many small files. If we would do file
level deduplication, i.e. generate one chunk per file, we end up with
more than 700000 chunks.

Instead, our current algorithm only produce large chunks with an
average chunks size of 4MB. With above data, this produce about 15000
chunks (factor 50 less chunks).
