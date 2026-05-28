output "vpc_id" {
  value = module.network.vpc_id
}

output "fqdn" {
  value = module.dns.fqdn
}
