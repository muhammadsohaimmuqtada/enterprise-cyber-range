FROM nginx:alpine

COPY htdocs/ /usr/share/nginx/html/

# Serves the fake "ISP" page on 80 so the attacker has an upstream-looking hop
# on the external segment (healthcheck is defined in docker-compose.yml).
