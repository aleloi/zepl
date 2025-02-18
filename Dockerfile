# For testing on linux. 
FROM ubuntu:latest

RUN apt-get update && apt-get install -y \
    curl \
    xz-utils \
    gdb \
  && rm -rf /var/lib/apt/lists/*

RUN curl -LO https://ziglang.org/download/0.13.0/zig-linux-aarch64-0.13.0.tar.xz \
    && tar -xf zig-linux-aarch64-0.13.0.tar.xz \
    && mv zig-linux-aarch64-0.13.0 /usr/local/ \
    && rm zig-linux-aarch64-0.13.0.tar.xz

# Add Zig to PATH
ENV PATH="/usr/local/zig-linux-aarch64-0.13.0:${PATH}"

WORKDIR /app

COPY build.zig build.zig.zon .
COPY src src

RUN zig build

ENTRYPOINT ["./zig-out/bin/zepl"]
