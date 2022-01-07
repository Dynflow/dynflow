FROM alpine:3.15 as builder
RUN apk add -U go
ADD ./ work/
RUN cd /work && \
    go build

FROM scratch
COPY --from=builder /work/expand /expand
CMD ["/expand"]
