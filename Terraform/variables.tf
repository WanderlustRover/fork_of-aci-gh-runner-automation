variable "location" {
  type = string


  validation {
    condition     = contains(["item1", "item2", "item3"], var.test_variable)
    error_message = "Valid values for var: test_variable are (item1, item2, item3)."
  }
}

variable "rg_name" {
  type    = string
  default = "rg-aci-ghrunners"
}

variable "vnet_name" {
  type    = string
  default = "test-vnet"

}

variable "gh_pat" {
  default = ""
}

variable "gh_repo_url" {
  default = ""
}
