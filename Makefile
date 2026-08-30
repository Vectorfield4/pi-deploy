.PHONY: init up down logs setup restart backup install-packages update-skills update

init:
	@bash scripts/init.sh

install-packages:
	@bash scripts/install-packages.sh

setup:
	@bash scripts/setup.sh

up: init
	@docker compose up -d

update-skills:
	@docker compose restart pi

update:
	@git pull --ff-only
	@docker compose build pi
	@docker compose up -d --force-recreate pi
	@bash scripts/install-packages.sh
	@bash scripts/setup-cron-jobs.sh

restart:
	@docker compose up -d --force-recreate pi

down:
	@docker compose down

logs:
	@docker compose logs -f

backup:
	@bash scripts/backup.sh