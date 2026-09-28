FROM node:24.21.0-bookworm-slim

WORKDIR /repro/app
COPY app/package.json ./
RUN npm install --no-audit --no-fund

WORKDIR /repro
COPY app ./app
COPY packages ./packages
COPY scripts/run-cycle.sh ./scripts/run-cycle.sh
RUN chmod 0755 ./scripts/run-cycle.sh

WORKDIR /repro/app
ENTRYPOINT ["../scripts/run-cycle.sh"]
CMD ["/evidence"]
