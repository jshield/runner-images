packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "1.4.5"
    }
  }
}

locals {
  image_os = "oracle_810"

  toolset_file_name = "toolset-2204.json"

  image_folder            = "/imagegeneration"
  helper_script_folder    = "/imagegeneration/helpers"
  installer_script_folder = "/imagegeneration/installers"
  imagedata_file          = "/imagegeneration/imagedata.json"

  managed_image_name = var.managed_image_name != "" ? var.managed_image_name : "packer-${var.image_os}-${var.image_version}"
}

variable "allowed_inbound_ip_addresses" {
  type    = list(string)
  default = []
}

variable "azure_tags" {
  type    = map(string)
  default = {}
}

variable "build_resource_group_name" {
  type    = string
  default = "${env("BUILD_RESOURCE_GROUP_NAME")}"
}

variable "client_cert_path" {
  type    = string
  default = "${env("ARM_CLIENT_CERT_PATH")}"
}

variable "client_id" {
  type    = string
  default = "${env("ARM_CLIENT_ID")}"
}

variable "client_secret" {
  type      = string
  default   = "${env("ARM_CLIENT_SECRET")}"
  sensitive = true
}

variable "image_version" {
  type    = string
  default = "dev"
}

variable "install_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "location" {
  type    = string
  default = "${env("ARM_RESOURCE_LOCATION")}"
}

variable "managed_image_name" {
  type    = string
  default = ""
}

variable "managed_image_resource_group_name" {
  type    = string
  default = "${env("ARM_RESOURCE_GROUP")}"
}

variable "private_virtual_network_with_public_ip" {
  type    = bool
  default = false
}

variable "subscription_id" {
  type    = string
  default = "${env("ARM_SUBSCRIPTION_ID")}"
}

variable "temp_resource_group_name" {
  type    = string
  default = "${env("TEMP_RESOURCE_GROUP_NAME")}"
}

variable "tenant_id" {
  type    = string
  default = "${env("ARM_TENANT_ID")}"
}

variable "virtual_network_name" {
  type    = string
  default = "${env("VNET_NAME")}"
}

variable "virtual_network_resource_group_name" {
  type    = string
  default = "${env("VNET_RESOURCE_GROUP")}"
}

variable "virtual_network_subnet_name" {
  type    = string
  default = "${env("VNET_SUBNET")}"
}

variable "vm_size" {
  type    = string
  default = "Standard_D4s_v4"
}

source "azure-arm" "build_image" {
  location = "${var.location}"

  // Auth
  tenant_id        = "${var.tenant_id}"
  subscription_id  = "${var.subscription_id}"
  client_id        = "${var.client_id}"
  client_secret    = "${var.client_secret}"
  client_cert_path = "${var.client_cert_path}"

  // Base image
  image_offer     = "Oracle-Linux"
  image_publisher = "Oracle"
  image_sku       = "ol810-lvm-gen2"

  // Target location
  managed_image_name = "${local.managed_image_name}"
  managed_image_resource_group_name = "${var.managed_image_resource_group_name}"

  // Resource group for VM
  build_resource_group_name = "${var.build_resource_group_name}"
  temp_resource_group_name  = "${var.temp_resource_group_name}"

  // Networking for VM
  private_virtual_network_with_public_ip = "${var.private_virtual_network_with_public_ip}"
  virtual_network_resource_group_name    = "${var.virtual_network_resource_group_name}"
  virtual_network_name                   = "${var.virtual_network_name}"
  virtual_network_subnet_name            = "${var.virtual_network_subnet_name}"
  allowed_inbound_ip_addresses           = "${var.allowed_inbound_ip_addresses}"

  // VM Configuration
  vm_size         = "${var.vm_size}"
  os_disk_size_gb = "75"
  os_type         = "Linux"

  dynamic "azure_tag" {
    for_each = var.azure_tags
    content {
      name = azure_tag.key
      value = azure_tag.value
    }
  }
}

build {
  sources = ["source.azure-arm.build_image"]

  // Create folder to store temporary data
  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = ["mkdir ${local.image_folder}", "chmod 777 ${local.image_folder}"]
  }

  provisioner "file" {
    destination = "${local.helper_script_folder}"
    source      = "${path.root}/../scripts/helpers"
  }
/*
  // Add apt wrapper to implement retries
  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/../scripts/build/configure-apt-mock.sh"
  }

  // Install MS package repos, Configure apt
  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${local.helper_script_folder}","DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = [
      "${path.root}/../scripts/build/install-ms-repos.sh",
      "${path.root}/../scripts/build/configure-apt.sh"
    ]
  }
*/
  provisioner "shell" {
      execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
      inline = ["dnf -y install redhat-lsb-core"]
    }
  // Configure limits
  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/../scripts/build/configure-limits.sh"
  }

  provisioner "file" {
    destination = "${local.installer_script_folder}"
    source      = "${path.root}/../scripts/build"
  }

  provisioner "file" {
    destination = "${local.image_folder}"
    sources     = [
      "${path.root}/../assets/post-gen",
      "${path.root}/../scripts/tests"
    ]
  }

  provisioner "file" {
    destination = "${local.installer_script_folder}/toolset.json"
    source      = "${path.root}/../toolsets/${local.toolset_file_name}"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = ["mv ${local.image_folder}/post-gen ${local.image_folder}/post-generation"]
  }

  // Generate image data file
  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGEDATA_FILE=${local.imagedata_file}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/configure-image-data.sh"]
  }

  // Create /etc/environment, configure waagent etc.
  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGE_OS=${local.image_os}", "HELPER_SCRIPTS=${local.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/configure-environment.sh"]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive", "HELPER_SCRIPTS=${local.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${local.installer_script_folder}", "XRAY_VERSION=3.104.18"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = [
      "${path.root}/../../oracle/scripts/build/install-xray.sh"
    ]
  }

  provisioner "shell" {
    execute_command   = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    expect_disconnect = true
    inline            = ["echo 'Reboot VM'", "sudo reboot"]
  }

  provisioner "shell" {
    execute_command     = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    pause_before        = "1m0s"
    scripts             = ["${path.root}/../../oracle/scripts/build/cleanup.sh"]
    start_retry_timeout = "10m"
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPT_FOLDER=${local.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${local.installer_script_folder}", "IMAGE_FOLDER=${local.image_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/configure-system.sh"]
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = ["sleep 30", "/usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync"]
  }

}
