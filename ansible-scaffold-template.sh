#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="ansible-project"

echo "Creating complete enterprise Ansible project structure in ./${PROJECT_DIR}..."

# 1. Create complete directory tree
mkdir -p "${PROJECT_DIR}"/{collections,inventory/production/group_vars,inventory/staging/group_vars,playbooks,roles/webserver/{defaults,vars,tasks,handlers,templates,files,meta}}

# 2. Create ansible.cfg
cat << 'EOF' > "${PROJECT_DIR}/ansible.cfg"
[defaults]
inventory = inventory/production/hosts.yaml
roles_path = roles
remote_user = ubuntu
host_key_checking = False
retry_files_enabled = False
interpreter_python = auto_silent

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False
EOF

# 3. Create Collections Requirements
cat << 'EOF' > "${PROJECT_DIR}/collections/requirements.yml"
---
collections:
  - name: community.general
    version: ">=7.0.0"
EOF

# 4. Create Production Inventory and Group Variables
cat << 'EOF' > "${PROJECT_DIR}/inventory/production/hosts.yaml"
all:
  children:
    webservers:
      hosts:
        web01.production.internal:
          ansible_host: 192.168.10.10
        web02.production.internal:
          ansible_host: 192.168.10.11
EOF

cat << 'EOF' > "${PROJECT_DIR}/inventory/production/group_vars/all.yml"
---
environment_name: "production"
ntp_servers:
  - time.google.com
EOF

cat << 'EOF' > "${PROJECT_DIR}/inventory/production/group_vars/webservers.yml"
---
app_version: "v2.0.1"
maintenance_mode: false
EOF

# 5. Create Staging Inventory and Group Variables
cat << 'EOF' > "${PROJECT_DIR}/inventory/staging/hosts.yaml"
all:
  children:
    webservers:
      hosts:
        web01.staging.internal:
          ansible_host: 192.168.20.10
EOF

cat << 'EOF' > "${PROJECT_DIR}/inventory/staging/group_vars/all.yml"
---
environment_name: "staging"
ntp_servers:
  - time.google.com
EOF

cat << 'EOF' > "${PROJECT_DIR}/inventory/staging/group_vars/webservers.yml"
---
app_version: "v2.1.0-rc1"
maintenance_mode: true
EOF

# 6. Create Master Orchestration Playbook
cat << 'EOF' > "${PROJECT_DIR}/playbooks/site.yml"
---
- name: Orchestrate enterprise webserver tier
  hosts: webservers
  gather_facts: yes
  roles:
    - role: webserver
EOF

# 7. Populate Role: defaults/main.yml (Low-priority variables)
cat << 'EOF' > "${PROJECT_DIR}/roles/webserver/defaults/main.yml"
---
nginx_port: 80
nginx_worker_processes: "auto"
nginx_max_clients: 1024
EOF

# 8. Populate Role: vars/main.yml (High-priority role internal variables)
cat << 'EOF' > "${PROJECT_DIR}/roles/webserver/vars/main.yml"
---
web_root_dir: "/var/www/html"
nginx_user: "www-data"
EOF

# 9. Populate Role: tasks/main.yml (Execution sequence including pre/post templates)
cat << 'EOF' > "${PROJECT_DIR}/roles/webserver/tasks/main.yml"
---
- name: PRE-DEPLOYMENT | Deploy maintenance landing page template
  template:
    src: maintenance.html.j2
    dest: "{{ web_root_dir }}/maintenance.html"
    owner: "{{ nginx_user }}"
    group: "{{ nginx_user }}"
    mode: '0644'
  when: maintenance_mode | bool

- name: Install Nginx web server package
  apt:
    name: nginx
    state: present
    update_cache: yes

- name: Deploy static baseline assets from files/ directory
  copy:
    src: index.html
    dest: "{{ web_root_dir }}/static_index.html"
    owner: "{{ nginx_user }}"
    group: "{{ nginx_user }}"
    mode: '0644'

- name: Deploy custom Nginx configuration template
  template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
    owner: root
    group: root
    mode: '0644'
  notify: Restart Nginx

- name: POST-DEPLOYMENT | Deploy system operational status verification template
  template:
    src: status.html.j2
    dest: "{{ web_root_dir }}/index.html"
    owner: "{{ nginx_user }}"
    group: "{{ nginx_user }}"
    mode: '0644'
  when: not (maintenance_mode | bool)
EOF

# 10. Populate Role: handlers/main.yml
cat << 'EOF' > "${PROJECT_DIR}/roles/webserver/handlers/main.yml"
---
- name: Restart Nginx
  service:
    name: nginx
    state: restarted
EOF

# 11. Populate Role: templates/ (Nginx Config + Pre/Post Templates)
cat << 'EOF' > "${PROJECT_DIR}/roles/webserver/templates/nginx.conf.j2"
user {{ nginx_user }};
worker_processes {{ nginx_worker_processes }};
pid /run/nginx.pid;

events {
    worker_connections {{ nginx_max_clients }};
}

http {
    server {
        listen {{ nginx_port }};
        server_name localhost;

        location / {
            root {{ web_root_dir }};
            index index.html index.htm;
        }
    }
}
EOF

cat << 'EOF' > "${PROJECT_DIR}/roles/webserver/templates/maintenance.html.j2"
<!DOCTYPE html>
<html>
<head>
    <title>Scheduled Maintenance - {{ environment_name | upper }}</title>
</head>
<body style="font-family: sans-serif; text-align: center; padding-top: 50px; background-color: #f8d7da;">
    <h1 style="color: #721c24;">System Maintenance Underway</h1>
    <p>Environment: <strong>{{ environment_name }}</strong></p>
    <p>We are currently updating our infrastructure. Please check back shortly.</p>
</body>
</html>
EOF

cat << 'EOF' > "${PROJECT_DIR}/roles/webserver/templates/status.html.j2"
<!DOCTYPE html>
<html>
<head>
    <title>Service Operational - {{ environment_name | upper }}</title>
</head>
<body style="font-family: sans-serif; text-align: center; padding-top: 50px; background-color: #d4edda;">
    <h1 style="color: #155724;">System Online & Verified</h1>
    <p>Environment: <strong>{{ environment_name }}</strong></p>
    <p>Active Deployed Version: <strong>{{ app_version }}</strong></p>
    <p>Managed cleanly via Ansible Automation</p>
</body>
</html>
EOF

# 12. Populate Role: files/ (Static asset)
cat << 'EOF' > "${PROJECT_DIR}/roles/webserver/files/index.html"
<!DOCTYPE html>
<html>
<head><title>Static Asset Fallback</title></head>
<body><p>Static backup asset file deployed from files/ directory.</p></body>
</html>
EOF

# 13. Populate Role: meta/main.yml (Role metadata and dependencies)
cat << 'EOF' > "${PROJECT_DIR}/roles/webserver/meta/main.yml"
---
galaxy_info:
  author: "Ansible DevOps Engineer"
  description: "Enterprise webserver configuration role with pre/post hooks"
  company: "Internal Infrastructure"
  license: "MIT"
  min_ansible_version: "2.14"
  platforms:
    - name: Ubuntu
      versions:
        - jammy
        - noble

dependencies: []
EOF

# 14. Create README
cat << 'EOF' > "${PROJECT_DIR}/README.md"
# Enterprise Ansible Automation Framework

Production-ready structure incorporating environment isolation, full role separation (`defaults`, `vars`, `tasks`, `handlers`, `templates`, `files`, `meta`), and pre/post rollout lifecycle templates.

## Execution
```bash
ansible-playbook -i inventory/production/hosts.yaml playbooks/site.yml
EOF
