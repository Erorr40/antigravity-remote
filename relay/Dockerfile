FROM node:20-alpine

WORKDIR /app

COPY package.json server.js ./

EXPOSE 8765

ENV PORT=8765

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8765/health || exit 1

CMD ["node", "server.js"]
