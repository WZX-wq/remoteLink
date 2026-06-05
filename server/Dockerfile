FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY src ./src
COPY public ./public

ENV KQ_API_HOST=0.0.0.0
ENV KQ_API_PORT=21120

EXPOSE 21120

CMD ["npm", "start"]
