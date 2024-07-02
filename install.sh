#!/bin/bash

set -e

# Função para exibir título
function titulo() {
    echo "=========================="
    echo "$1"
    echo "=========================="
}

# Solicitar ao usuário as informações necessárias
read -p 'Digite o nome do usuário para o banco de dados: ' DB_USER
read -sp 'Digite a senha desejada para o banco de dados: ' DB_PASSWORD
echo
read -p 'Digite seu domínio (exemplo: suodominio.com): ' DOMAIN

# Atualizar e instalar pacotes necessários
titulo "Atualizando o sistema e instalando pacotes necessários"
sudo apt update -y
sudo apt upgrade -y
sudo apt -y install php8.1-intl curl nginx mysql-server

# Instalar Composer
titulo "Instalando Composer"
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

# Criar diretório para o painel de controle e navegar para ele
titulo "Criando diretório para o painel de controle"
sudo mkdir -p /var/www/controlpanel && cd /var/www/controlpanel

# Clonar repositório do painel de controle
titulo "Clonando repositório do painel de controle"
sudo git clone https://github.com/Ctrlpanel-gg/panel.git ./

# Configurar o banco de dados
titulo "Configurando o banco de dados"
sudo mysql -u root -p -e "
CREATE DATABASE controlpanel;
CREATE USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON controlpanel.* TO '$DB_USER'@'127.0.0.1';
FLUSH PRIVILEGES;
EXIT;"

# Configurar Nginx
titulo "Configurando Nginx"
sudo tee /etc/nginx/sites-available/ctrlpanel.conf > /dev/null <<EOL
server {
    listen 80;
    root /var/www/controlpanel/public;
    index index.php index.html index.htm;
    server_name $DOMAIN;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

# Habilitar configuração do Nginx
titulo "Habilitando configuração do Nginx"
sudo ln -s /etc/nginx/sites-available/ctrlpanel.conf /etc/nginx/sites-enabled/ctrlpanel.conf

# Verificar erros no Nginx
titulo "Verificando erros no Nginx"
sudo nginx -t

# Reiniciar Nginx
titulo "Reiniciando Nginx"
sudo systemctl restart nginx

# Adicionar SSL usando Certbot
titulo "Adicionando SSL usando Certbot"
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d $DOMAIN

# Navegar de volta para o diretório do painel de controle
cd /var/www/controlpanel

# Instalar pacotes do Composer
titulo "Instalando pacotes do Composer"
sudo composer install --no-dev --optimize-autoloader

# Configurar permissões
titulo "Configurando permissões"
sudo chown -R www-data:www-data /var/www/controlpanel/
sudo chmod -R 755 storage/* bootstrap/cache/

# Criar Crontab para tarefas agendadas
titulo "Criando Crontab para tarefas agendadas"
(crontab -l ; echo "* * * * * php /var/www/controlpanel/artisan schedule:run >> /dev/null 2>&1") | crontab -

# Criar serviço do Queue Worker
titulo "Criando serviço do Queue Worker"
sudo tee /etc/systemd/system/ctrlpanel.service > /dev/null <<EOL
[Unit]
Description=Ctrlpanel Queue Worker

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/controlpanel/artisan queue:work --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target
EOL

# Habilitar e iniciar o serviço do Queue Worker
titulo "Habilitando e iniciando o serviço do Queue Worker"
sudo systemctl enable --now ctrlpanel.service

titulo "Instalação completa!"
echo "Acesse o painel através do seu navegador em https://$DOMAIN/install para concluir a instalação."
