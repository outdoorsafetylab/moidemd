# Rasters are copied in as published, and checked against recorded digests
# when fetched. See README.md.
FROM outdoorsafetylab/demd:2.0.0

COPY dem/2025/ /var/lib/dem/

CMD ["sh", "-c", "exec /usr/sbin/demd -p $PORT -A \"$AUTH\" /var/lib/dem/"]
