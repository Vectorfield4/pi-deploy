.PHONY: init up down logs setup restart backup install-packages update-skills

init:
	@test -f .env || cp .env.example .env
	@test -d workspace || mkdir workspace
	@test -d backups || mkdir backups

install-packages:
	docker compose exec pi pi install npm:pi-subagents
	docker compose exec pi pi install npm:pi-true-queue
	docker compose exec pi pi install npm:pi-mcp-adapter
	docker compose exec pi pi install npm:pi-context-cap
	docker compose exec pi pi install npm:@bytesbrains/pi-telegram-bridge
	docker compose exec pi pi install npm:ping-a-human-pi
	docker compose exec pi pi install npm:pi-memory
	docker compose exec pi pi install npm:@upstash/context7-pi

update-skills:
	docker compose restart pi

setup: init
	docker compose up -d memory-db embedding dense-mem
	@echo "Waiting for dense-mem to be healthy..."
	@sleep 30
	docker compose up -d --build pi
	bash scripts/memory-bootstrap.sh
	$(MAKE) install-packages

up: init
	docker compose up -d

restart:
	docker compose up -d --force-recreate pi

down:
	docker compose down

logs:
	docker compose logs -f

backup:
	bash scripts/backup.sh
