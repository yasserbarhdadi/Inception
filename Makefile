NAME		= inception
LOGIN		= yabarhda
DATA_DIR	= /home/$(LOGIN)/data
COMPOSE		= docker compose --env-file srcs/.env -f srcs/docker-compose.yml

all: mkdirs up

up:
	$(COMPOSE) up --build -d

down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop

start:
	$(COMPOSE) start

restart: down up

mkdirs:
	mkdir -p $(DATA_DIR)/wordpress
	mkdir -p $(DATA_DIR)/mariadb

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

clean: down
	docker system prune -f

fclean: down
	docker volume rm $(NAME)_wordpress_data $(NAME)_mariadb_data 2>/dev/null || true
	docker system prune -af
	sudo rm -rf $(DATA_DIR)/wordpress/*
	sudo rm -rf $(DATA_DIR)/mariadb/*

re: fclean all

.PHONY: all up down stop start restart mkdirs logs ps clean fclean re
