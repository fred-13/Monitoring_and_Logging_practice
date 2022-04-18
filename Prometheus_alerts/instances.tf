#-------------------G-Core cloud project------------#
data "gcore_project" "pr" {
  name = "a.meshcherakov"
}

data "gcore_region" "rg" {
  name = "Saint Petersburg"
}

data "gcore_image" "ubuntu" {
  name = "ubuntu-20.04"
  region_id = data.gcore_region.rg.id
  project_id = data.gcore_project.pr.id
}

data "gcore_securitygroup" "default" {
  name = "default"
  region_id = data.gcore_region.rg.id
  project_id = data.gcore_project.pr.id
}

#---------------Network-----------------#
resource "gcore_network" "network" {
  name = "network_otus"
  mtu = 1450
  type = "vxlan"
  region_id = data.gcore_region.rg.id
  project_id = data.gcore_project.pr.id
}

#--------------Subnet-----------------#
resource "gcore_subnet" "subnet" {
  name = "subnet_otus"
  cidr = "192.168.10.0/24"
  network_id = gcore_network.network.id
  dns_nameservers = ["8.8.4.4", "1.1.1.1"]

  host_routes {
    destination = "10.0.3.0/24"
    nexthop = "10.0.0.13"
  }

  gateway_ip = "192.168.10.1"
  region_id = data.gcore_region.rg.id
  project_id = data.gcore_project.pr.id
}

#-----------Fixed IP for Prometheus server-------------#
resource "gcore_reservedfixedip" "fixed_ip_prometheus" {
  project_id = data.gcore_project.pr.id
  region_id = data.gcore_region.rg.id
  type = "ip_address"
  network_id = gcore_network.network.id
  fixed_ip_address = "192.168.10.6"
  is_vip = false
}

#------------External IP for Prometheus server-------------#
resource "gcore_floatingip" "fip_prometheus" {
  project_id = data.gcore_project.pr.id
  region_id = data.gcore_region.rg.id
  fixed_ip_address = gcore_reservedfixedip.fixed_ip_prometheus.fixed_ip_address
  port_id = gcore_reservedfixedip.fixed_ip_prometheus.port_id
}

#-----------Fixed IP for Nginx server-------------#
resource "gcore_reservedfixedip" "fixed_ip_nginx" {
  project_id = data.gcore_project.pr.id
  region_id = data.gcore_region.rg.id
  type = "ip_address"
  network_id = gcore_network.network.id
  fixed_ip_address = "192.168.10.7"
  is_vip = false
}

#------------External IP for Nginx server-------------#
resource "gcore_floatingip" "fip_nginx" {
  project_id = data.gcore_project.pr.id
  region_id = data.gcore_region.rg.id
  fixed_ip_address = gcore_reservedfixedip.fixed_ip_nginx.fixed_ip_address
  port_id = gcore_reservedfixedip.fixed_ip_nginx.port_id
}

#-------------Volumes for Prometheus server-----------#
resource "gcore_volume" "prometheus_first_volume" {
  name = "boot volume"
  type_name = "ssd_hiiops"
  size = 10
  image_id = data.gcore_image.ubuntu.id
  region_id = data.gcore_region.rg.id
  project_id = data.gcore_project.pr.id
}

resource "gcore_volume" "prometheus_second_volume" {
  name = "second volume"
  type_name = "ssd_hiiops"
  size = 15
  region_id = data.gcore_region.rg.id
  project_id = data.gcore_project.pr.id
}

#-------------Volumes for Nginx server-----------#
resource "gcore_volume" "nginx_first_volume" {
  name = "boot volume"
  type_name = "ssd_hiiops"
  size = 10
  image_id = data.gcore_image.ubuntu.id
  region_id = data.gcore_region.rg.id
  project_id = data.gcore_project.pr.id
}

# output "floating_ip_external_prometheus" {
#   description = "External IP"
#   value       = gcore_floatingip.fip_prometheus
# }

# output "floating_ip_external_nginx" {
#   description = "External IP"
#   value       = gcore_floatingip.fip_nginx
# }

#-------------Prometheus instance-------------#
resource "gcore_instance" "prometheus_instance" {
  flavor_id = "g0-standard-2-4"
  name = "prometheus"
  keypair_name = "WSL"

  volume {
    source = "existing-volume"
    volume_id = gcore_volume.prometheus_first_volume.id
    boot_index = 0
  }

  volume {
    source = "existing-volume"
    volume_id = gcore_volume.prometheus_second_volume.id
    boot_index = 1
  }

  interface {
    type = "reserved_fixed_ip"
        port_id = gcore_reservedfixedip.fixed_ip_prometheus.port_id
        fip_source = "existing"
        existing_fip_id = gcore_floatingip.fip_prometheus.id
  }

  security_group {
    id = data.gcore_securitygroup.default.id
    name = "default"
  }

  metadata_map = {
    some_key = "some_value"
    stage = "dev"
  }

  configuration {
    key = "some_key"
    value = "some_data"
  }

  region_id = data.gcore_region.rg.id
  project_id = data.gcore_project.pr.id

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(pathexpand("~/.ssh/id_rsa"))
    host        = gcore_floatingip.fip_prometheus.floating_ip_address
  }

  provisioner "remote-exec" {
    inline = [
      "sudo pvcreate /dev/sdb",
      "sudo vgcreate vg_otus /dev/sdb",
      "sudo lvcreate -n lv_otus -l +100%FREE /dev/vg_otus",
      "sudo mkfs.ext4 /dev/vg_otus/lv_otus",
      "sudo mkdir /data",
      "sudo mount /dev/vg_otus/lv_otus /data",
    ]
  }

  provisioner "local-exec" {
    command = <<EOT
      ssh -o "StrictHostKeyChecking no" ubuntu@${gcore_floatingip.fip_prometheus.floating_ip_address}
      ansible-playbook -i ${gcore_floatingip.fip_prometheus.floating_ip_address}, prometheus.yaml -u ubuntu -b
  EOT
  }

}

#-------------Nginx instance-------------#
resource "gcore_instance" "nginx_instance" {
  flavor_id = "g0-standard-2-4"
  name = "nginx"
  keypair_name = "WSL"

  volume {
    source = "existing-volume"
    volume_id = gcore_volume.nginx_first_volume.id
    boot_index = 0
  }

  interface {
    type = "reserved_fixed_ip"
        port_id = gcore_reservedfixedip.fixed_ip_nginx.port_id
        fip_source = "existing"
        existing_fip_id = gcore_floatingip.fip_nginx.id
  }

  security_group {
    id = data.gcore_securitygroup.default.id
    name = "default"
  }

  metadata_map = {
    some_key = "some_value"
    stage = "dev"
  }

  configuration {
    key = "some_key"
    value = "some_data"
  }

  region_id = data.gcore_region.rg.id
  project_id = data.gcore_project.pr.id

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(pathexpand("~/.ssh/id_rsa"))
    host        = gcore_floatingip.fip_nginx.floating_ip_address
  }

  provisioner "remote-exec" {
    inline = [
      "hostname",
      "sudo apt-get update",
      "sudo apt-get install ca-certificates curl gnupg lsb-release -y",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update",
      "sudo apt-get install docker-ce docker-ce-cli containerd.io -y",
    ]
  }

  provisioner "local-exec" {
    command = <<EOT
      ssh -o "StrictHostKeyChecking no" ubuntu@${gcore_floatingip.fip_nginx.floating_ip_address}
      ansible-playbook -i ${gcore_floatingip.fip_nginx.floating_ip_address}, nginx.yaml -u ubuntu -b
  EOT
  }

}
