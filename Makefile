.DEFAULT_GOAL := help
.PHONY: help setup up down restart logs chat status test reset pull

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

setup: ## Bootstrap from a fresh clone (secrets, model config) and start
	./setup.sh

up: ## Start Hermes in the background
	docker compose up -d

down: ## Stop Hermes
	docker compose down

restart: ## Restart Hermes
	docker compose restart

logs: ## Tail logs
	docker compose logs -f

chat: ## Interactive CLI chat
	docker compose run --rm hermes chat

status: ## Show component status
	docker compose run --rm hermes status

test: ## Send a one-shot prompt to verify the model works
	docker compose run --rm --no-TTY hermes -z "Reply with exactly HERMES_OK and your model name."

pull: ## Pull the latest Hermes image
	docker compose pull

reset: ## DANGER: stop and delete all Hermes state (data/)
	docker compose down && rm -rf data
