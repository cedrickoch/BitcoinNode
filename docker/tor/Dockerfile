FROM alpine:3

# Data dir is created private to tor here, so a fresh named volume inherits
# this ownership and the container never needs root
RUN apk add --no-cache tor \
 && install -d -o tor -g tor -m 700 /var/lib/tor

COPY --chmod=755 entrypoint.sh /entrypoint.sh

USER tor

ENTRYPOINT ["/entrypoint.sh"]
