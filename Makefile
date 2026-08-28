.PHONY: init up down logs setup restart backup install-packages update-skills

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

restart:
	@docker compose up -d --force-recreate pi

down:
	@docker compose down

logs:
	@docker compose logs -f

backup:
	@bash scripts/backup.sh