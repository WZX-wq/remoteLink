# iOS Account Deletion API Contract

The iOS app sends an account-deletion request only after the user types `DELETE` in Personal center. Configure the complete HTTPS endpoint at build time:

```text
KQ_ACCOUNT_DELETE_URL=https://api-web.kunqiongai.com/api/auth/account/delete
```

The concrete path can differ, but the deployed endpoint must match this contract.

## Request

```http
POST /api/auth/account/delete HTTP/1.1
Authorization: Bearer <access-token>
Content-Type: application/json
Accept: application/json

{"confirmation":"DELETE"}
```

The server must authenticate the token, reject malformed confirmation text, and apply any required SMS or risk verification before accepting the request. It must not treat a client-side logout as account deletion.

## Success responses

Immediate deletion:

```json
{"success":true,"status":"deleted","message":"Account deleted."}
```

Asynchronous deletion request:

```json
{"success":true,"status":"pending","message":"Deletion request received."}
```

Return HTTP `200` for a completed deletion or `202` for a pending request. The client clears its local session only after receiving one of these successful responses.

## Failure responses

Return a non-2xx status with a user-readable `message`:

```json
{"success":false,"message":"Please verify your phone before deleting the account."}
```

The server must document any retention period, legal retention exception, cancellation window, and completion notification. If the account has an App Store auto-renewable subscription, the app warns users that they must cancel it through Apple separately.
