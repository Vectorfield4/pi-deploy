.PHONY: init up down logs setup restart backup install-packages update-skills

init:
	@if [ ! -f .env ]; then cp .env.example .env; else \
	  # Merge: add keys from .env.example that are missing in .env
	  grep -E '^[A-Z_]+=' .env.example | while IFS= read -r line; do \
	    key=$$(echo "$$line" | cut -d= -f1); \
	    if ! grep -q "^$$key=" .env 2>/dev/null; then echo "$$line" >> .env; fi; \
	  done; fi
	@test -d workspace || mkdir workspace
	@test -d backups || mkdir backups

# Source of truth for the package list is .pi/settings.json `packages`.
# This rule parses it and runs `pi install` for each entry. Idempotent.
install-packages:
	@packages=$$(node -e "console.log((JSON.parse(require('fs').readFileSync('.pi/settings.json','utf8')).packages||[]).join('\n'))"); \
	if [ -z "$$packages" ]; then echo "No packages in .pi/settings.json"; exit 0; fi; \
	echo "Installing $$(echo "$$packages" | wc -l) package(s)..."; \
	for pkg in $$packages; do \
		echo "  pi install $$pkg"; \
		docker compose exec -T pi pi install $$pkg || exit 1; \
	done

update-skills:
	docker compose restart pi

setup: init
	docker compose up -d memory-db embedding dense-mem
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
