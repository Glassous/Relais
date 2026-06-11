FROM alpine:latest

RUN apk --no-cache add ca-certificates tzdata

WORKDIR /app

# Copy the locally compiled Linux binary
COPY relais-backend .

EXPOSE 8184

CMD ["./relais-backend"]
