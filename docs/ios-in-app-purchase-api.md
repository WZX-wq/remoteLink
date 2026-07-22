# iOS StoreKit Verification Contract

App Store and TestFlight builds use Apple In-App Purchase for membership. They must not enable the internal external-payment build flag.

## Build configuration

Provide these values only through the release build environment:

```text
KQ_IOS_IAP_PRODUCTS={"1":"com.kunqiong.remotelink.member.monthly","2":"com.kunqiong.remotelink.member.quarterly"}
KQ_IOS_IAP_VERIFY_URL=https://membership.example.com/api/membership/apple/verify
```

The JSON key is the existing server membership package ID. Each value is the matching App Store Connect product ID. Product identifiers, Apple private keys, App Store Connect keys, and receipt-verification secrets must never be compiled into the Flutter client.

The verification URL must be a deployed authenticated `POST` route. It must
validate Apple transaction data server-side before granting membership and must
not trust a client-supplied package or expiry date.

## Verification request

```http
POST /api/membership/apple/verify HTTP/1.1
Authorization: Bearer <access-token>
Content-Type: application/json
Accept: application/json

{
  "package_id":"1",
  "product_id":"com.kunqiong.remotelink.member.monthly",
  "transaction_id":"<StoreKit transaction id>",
  "server_verification_data":"<StoreKit signed transaction data>",
  "local_verification_data":"<StoreKit local transaction data>",
  "source":"app_store"
}
```

The server must validate the signed transaction with Apple, confirm that `product_id` belongs to `package_id`, reject replayed or revoked transactions, update the existing membership entitlement atomically, and return a user-readable result.

## Subscription lifecycle notifications

Configure the App Store Server Notifications V2 URL to the deployed API route:

```text
https://<public-host>/kq-api/api/membership/apple/notifications
```

The notification route does not trust the received JWS as an entitlement. It
only extracts a transaction ID and then retrieves that transaction again from
the App Store Server API before changing membership data. Renewals refresh the
stored expiry. Revoked purchases mark only the matching Apple order inactive
and then recalculate the user's local membership from any remaining paid order.

Notifications received before the app has verified and bound the original
transaction to an account are accepted without granting membership. The next
client verification establishes ownership safely.

## Verification response

```json
{"success":true,"code":200,"message":"Membership entitlement updated."}
```

Any non-2xx response, `success:false`, or nonzero/non-200 `code` fails the transaction. The client refreshes membership and completes the StoreKit transaction only after this response is successful. Failed verification remains recoverable through **Restore Apple purchases**.

## App Store Connect setup

1. Create a non-consumable product or auto-renewable subscription for every mapped package.
2. For subscription products, place related tiers in one subscription group.
3. Make products available for review and verify them with a Sandbox Apple ID on a physical iPhone.
4. Provide the review team with a test account and explain the remote-desktop membership entitlement in App Review notes.
