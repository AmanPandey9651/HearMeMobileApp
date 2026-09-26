# Security action required before production

The uploaded backend/frontend source contains production-style credentials directly in committed configuration/source files. No credential values are copied into this mobile project.

Before deploying or sharing the repositories, rotate and move to environment variables/secrets management at least these credential classes:

- PostgreSQL/Aiven database password and any embedded database connection string
- JWT signing secret
- Razorpay secret
- Gmail SMTP/app password
- Cloudinary API secret
- Google OAuth client secret
- SMS gateway API key

Also remove direct database credentials from the Vite/frontend configuration. A browser/frontend build must never contain a database password or privileged database connection string.
