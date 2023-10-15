FROM node:lts-alpine3.18

WORKDIR /usr/src/app

COPY . . 

RUN npm ci && npm run build

EXPOSE 3001

CMD ["npm", "run", "start:prod"]