FROM node:22-alpine

WORKDIR /app

COPY package.json .
RUN npm install --omit=dev

COPY app.js .
COPY public ./public

# Writable data dir for posts.json (mount a volume here to persist)
RUN mkdir -p data && chown node data

EXPOSE 3000

# Run as non-root
USER node

CMD ["node", "app.js"]
