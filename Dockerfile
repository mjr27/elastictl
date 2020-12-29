FROM nimlang/nim:1.2.6 as BUILD-MUSL

RUN apt-get update && apt-get install -y musl-tools
WORKDIR /app

COPY *.nimble ./
RUN nimble install -d -y

COPY src ./src
RUN nimble static -y
RUN ls -l  /app/dist

FROM alpine
COPY --from=BUILD-MUSL /app/dist/elastictl /elastictl
ENTRYPOINT [ "/elastictl" ]
