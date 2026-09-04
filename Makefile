.PHONY: init up down logs setup restart backup install-packages update-skills update \
	jaeger-up jaeger-down jaeger-logs jaeger-restart build-memory

init:
	@bash scripts/init.sh

install-packages:
	@bash scripts/install-packages.sh

setup:
	@bash scripts/setup.sh

build-memory:
	@bash scripts/build-memory.sh

up: init
	@docker compose up -d

update-skills:
	@docker compose restart pi

update:
	@git pull --ff-only
	@chmod +x scripts/*.sh # pull may reset to 100644 in index; cron needs +x
	@docker compose build pi
	@docker compose up -d --force-recreate pi
	@bash scripts/install-packages.sh
	@bash scripts/setup-cron-jobs.sh
	@docker compose up -d jaeger # tolerant: extension drops until Jaeger up

restart:
	@git pull --ff-only
	@chmod +x scripts/*.sh
	@docker compose up -d --force-recreate pi

down:
	@docker compose down

logs:
	@docker compose logs -f

backup:
	@bash scripts/backup.sh

jaeger-up:
	@docker compose up -d jaeger

jaeger-down:
	@docker compose stop jaeger

jaeger-restart:
	@docker compose restart jaeger

jaeger-logs:
	@docker compose logs -f jaeger