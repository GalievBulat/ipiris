terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.84"
    }
  }
}

provider "yandex" {
  token     = var.yc_auth_token
  cloud_id  = var.yc_project_id
  folder_id = var.yc_directory_id
  zone      = "ru-central1-a"
}

resource "yandex_vpc_network" "main_network" {
  name = "b-network"
}

resource "yandex_vpc_subnet" "main_subnet" {
  name           = "b-subnet"
  network_id     = yandex_vpc_network.main_network.id
  v4_cidr_blocks = ["10.0.0.0/24"]
  zone           = "ru-central1-a"
}

resource "tls_private_key" "vm_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_file" "private_key_file" {
  content  = tls_private_key.vm_ssh_key.private_key_pem
  filename = "./vm_private_key"
}

resource "null_resource" "set_key_permissions" {
  depends_on = [local_file.private_key_file]

  provisioner "local-exec" {
    command = "chmod 600 ./vm_private_key"
  }
}

resource "yandex_compute_instance" "docker_server" {
  name        = "docker-host"
  platform_id = "standard-v3"

  resources {
    cores         = 2
    memory        = 4096
    core_fraction = 100
  }

  boot_disk {
    initialize_params {
      image_id = "fd8bpal18cm4kprpjc2m" # Ubuntu 24.04 LTS Image
      size     = 20
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.main_subnet.id
    nat       = true
  }

  metadata = {
    user-data = <<-EOF
      #cloud-config
      ssh_pwauth: no
      users:
        - name: ipiris
          groups: sudo
          sudo: 'ALL=(ALL) NOPASSWD:ALL'
          shell: /bin/bash
          ssh_authorized_keys:
            - ${tls_private_key.vm_ssh_key.public_key_openssh}

      write_files:
      - path: /etc/sudoers.d/ipiris
        content: "ipiris ALL=(ALL) NOPASSWD:ALL"
        permissions: '0440'

      runcmd:
        - [ sudo, snap, install, docker ]
        - [ sudo, systemctl, daemon-reload ]
        - [ sudo, systemctl, enable, snap.docker.dockerd.service ]
        - [ sudo, systemctl, start, snap.docker.dockerd.service ]
        - [ sudo, systemctl, restart, snap.docker.dockerd.service ]
        - [ sleep, 10 ]
        - [ sudo, docker, run, -d, --restart=always, -p, "80:8080", jmix/jmix-bookstore ]
    EOF
  }
}

output "ssh_access" {
  value = "ssh -i ./vm_private_key ipiris@${yandex_compute_instance.docker_server.network_interface.0.nat_ip_address}"
}

output "app_url" {
  value = "http://${yandex_compute_instance.docker_server.network_interface.0.nat_ip_address}:80"
}

variable "yc_auth_token" {}
variable "yc_project_id" {}
variable "yc_directory_id" {}
