# Use the official Nextcloud image as the base image
FROM nextcloud:latest

# Expose the default Nextcloud port
EXPOSE 80

# Set the default command to start Nextcloud
CMD ["apache2-foreground"]