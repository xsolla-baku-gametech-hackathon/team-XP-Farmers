FROM node:22-alpine
WORKDIR /app
COPY server.mjs ./
ENV HOST=0.0.0.0 PORT=8787
USER node
EXPOSE 8787
CMD ["node", "server.mjs"]
