FROM ubuntu:bionic

RUN apt-get update \
    && apt-get install -y acl libuuid1 libattr1 build-essential clang-10 git libacl1-dev uuid-dev curl \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile=minimal

WORKDIR /build
