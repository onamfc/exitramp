output "exitramp_ip" {
  description = "The static IP to hand to your vendor for allowlisting."
  value       = aws_eip.gateway.public_ip
}

output "ssh_command" {
  description = "SSH into the gateway as admin."
  value       = "ssh ubuntu@${aws_eip.gateway.public_ip}"
}

output "next_steps" {
  description = "What to do after apply."
  value       = <<-EOT
    1. Give this IP to your vendor for allowlisting: ${aws_eip.gateway.public_ip}
    2. Wait ~2 minutes for cloud-init to finish, then create your config:
         ssh ubuntu@${aws_eip.gateway.public_ip} 'sudo tail -5 /var/log/cloud-init-output.log'
         scp ../../add-peer.sh ../../remove-peer.sh ../../list-peers.sh ubuntu@${aws_eip.gateway.public_ip}:
         ssh ubuntu@${aws_eip.gateway.public_ip} 'chmod +x add-peer.sh && sudo ./add-peer.sh yourname'
    3. Copy the config down and import it into the WireGuard app:
         scp ubuntu@${aws_eip.gateway.public_ip}:yourname.conf .
    4. Connect, then verify: ./client/check-ip.sh ${aws_eip.gateway.public_ip}
  EOT
}
