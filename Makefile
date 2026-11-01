COMPOSE ?= docker compose
SHELL := /bin/bash
.DEFAULT_GOAL := help
.PHONY: help up down reset status logs-fw logs-web blue clean

help: ## show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-9s %s\n", $$1, $$2}'

up: ## start the range (docker compose up -d)
	$(COMPOSE) up -d

down: ## stop the range (keeps volumes)
	$(COMPOSE) down

reset: ## full reset: down -v, wipe state volumes, start fresh (dc01 re-provisions)
	$(COMPOSE) down -v --remove-orphans
	$(COMPOSE) up -d

status: ## compose status + firewall forward-chain counters
	$(COMPOSE) ps
	@echo "--- fw forward-chain counters ---"
	-@docker exec fw nft list chain inet filter forward 2>/dev/null || echo "fw not running"

logs-fw: ## follow fw container logs (stdout mirror of deny lines)
	docker logs -f fw

logs-web: ## follow web01 container logs (nginx + portal + gunicorn)
	docker logs -f web01

blue: ## start the range including the SIEM (blue profile; needs ~4 GB RAM)
	$(COMPOSE) --profile blue up -d

clean: ## stop and remove containers, volumes, and locally built images
	$(COMPOSE) down -v --rmi local --remove-orphans
