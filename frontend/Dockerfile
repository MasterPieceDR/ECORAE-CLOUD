FROM node:22-alpine AS compilacion
WORKDIR /web
COPY package*.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build
FROM nginx:1.29-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=compilacion /web/dist/ /usr/share/nginx/html/
EXPOSE 80
