# Frontend: sirve con nginx la versión ya compilada (dist/). En AWS, dist/ va a S3 y CloudFront hace lo que hace nginx aquí.
# Para recompilar después de cambiar el código:  npm ci && npm run build   (o usa Dockerfile.compilar)
FROM nginx:1.29-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY dist/ /usr/share/nginx/html/
EXPOSE 80
