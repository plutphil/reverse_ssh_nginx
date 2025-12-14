FROM alpine:3.19

RUN apk add --no-cache \
    nginx \
    openssh-client \
    autossh \
    openssl \
    bash \
    jq

COPY rootfs /

RUN chmod +x /usr/bin/run.sh

CMD ["/usr/bin/run.sh"]
