{ pkgs, lib, ... }:
# DigitalOcean networking via metadata API.
# DO does not provide a DHCP server — IP assignment is static via cloud-init.
# This module brings up the interface with link-local addressing, fetches the
# real IP/gateway/DNS from http://169.254.169.254, and applies it.
{
  # Disable dhcpcd — no DHCP server on DO
  networking.useDHCP = false;
  networking.dhcpcd.enable = false;

  # Use systemd-networkd for interface management
  systemd.network.enable = true;

  # Bring up the public interface with link-local addressing only.
  # This allows reaching the metadata API at 169.254.169.254.
  systemd.network.networks."10-do-public" = {
    matchConfig.Name = "en* eth*";
    networkConfig = {
      LinkLocalAddressing = "ipv4";
      LLDP = false;
      EmitLLDP = false;
    };
  };

  # Fetch network config from DO metadata and apply it
  systemd.services.do-configure-network = {
    description = "Configure networking from DigitalOcean metadata";
    after = [ "systemd-networkd.service" "systemd-networkd-wait-online.service" ];
    wants = [ "systemd-networkd.service" ];
    before = [ "network-online.target" "sshd.service" ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [ curl iproute2 jq gawk ];

    script = ''
      set -euo pipefail

      IFACE=""
      # Find the first non-loopback interface
      for i in /sys/class/net/*; do
        name=$(basename "$i")
        if [ "$name" != "lo" ]; then
          IFACE="$name"
          break
        fi
      done

      if [ -z "$IFACE" ]; then
        echo "ERROR: No network interface found"
        exit 1
      fi

      echo "Using interface: $IFACE"

      # Wait for link-local address (up to 30 seconds)
      for attempt in $(seq 1 30); do
        if ip addr show dev "$IFACE" | grep -q "169.254."; then
          echo "Link-local address acquired"
          break
        fi
        echo "Waiting for link-local address... ($attempt/30)"
        sleep 1
      done

      # Ensure route to metadata API exists
      ip route add 169.254.169.254/32 dev "$IFACE" 2>/dev/null || true

      # Fetch metadata
      echo "Fetching DO metadata..."
      METADATA=$(curl -sf --connect-timeout 10 --retry 5 --retry-delay 2 http://169.254.169.254/metadata/v1.json)

      # Extract public interface config
      IP=$(echo "$METADATA" | jq -r '.interfaces.public[0].ipv4.ip_address')
      NETMASK=$(echo "$METADATA" | jq -r '.interfaces.public[0].ipv4.netmask')
      GATEWAY=$(echo "$METADATA" | jq -r '.interfaces.public[0].ipv4.gateway')
      DNS=$(echo "$METADATA" | jq -r '.dns.nameservers | join(" ")')

      # Convert netmask to CIDR
      CIDR=$(echo "$NETMASK" | awk -F. '{
        split($0, a, ".");
        c=0;
        for(i=1;i<=4;i++) {
          b=a[i];
          while(b>0) { c+=b%2; b=int(b/2) }
        }
        print c
      }')

      echo "Configuring: $IP/$CIDR via $GATEWAY (DNS: $DNS)"

      # Apply network config
      ip addr flush dev "$IFACE"
      ip addr add "$IP/$CIDR" dev "$IFACE"
      ip route add default via "$GATEWAY" dev "$IFACE"

      # Configure DNS
      mkdir -p /etc
      printf "nameserver %s\n" $DNS > /etc/resolv.conf

      # Also configure private interface if present
      PRIV_IP=$(echo "$METADATA" | jq -r '.interfaces.private[0].ipv4.ip_address // empty')
      if [ -n "$PRIV_IP" ]; then
        PRIV_NETMASK=$(echo "$METADATA" | jq -r '.interfaces.private[0].ipv4.netmask')
        PRIV_CIDR=$(echo "$PRIV_NETMASK" | awk -F. '{
          split($0, a, ".");
          c=0;
          for(i=1;i<=4;i++) {
            b=a[i];
            while(b>0) { c+=b%2; b=int(b/2) }
          }
          print c
        }')

        # Find second interface
        PRIV_IFACE=""
        for i in /sys/class/net/*; do
          name=$(basename "$i")
          if [ "$name" != "lo" ] && [ "$name" != "$IFACE" ]; then
            PRIV_IFACE="$name"
            break
          fi
        done

        if [ -n "$PRIV_IFACE" ]; then
          ip addr flush dev "$PRIV_IFACE"
          ip addr add "$PRIV_IP/$PRIV_CIDR" dev "$PRIV_IFACE"
          echo "Configured private: $PRIV_IP/$PRIV_CIDR on $PRIV_IFACE"
        fi
      fi

      echo "Network configured successfully"
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  # Mark network as online after our service runs
  systemd.services.do-network-online = {
    description = "Signal network online after DO metadata config";
    after = [ "do-configure-network.service" ];
    requires = [ "do-configure-network.service" ];
    before = [ "network-online.target" ];
    wantedBy = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
    };
  };
}
