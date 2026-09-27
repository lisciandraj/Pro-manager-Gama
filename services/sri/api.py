"""Private signer/transport service for the Coco Supabase Edge Function.

Run behind HTTPS; the PKCS#12 and password are environment-only and never
returned to the browser or saved in the database.
"""
import base64
import hashlib
import hmac
import os
import smtplib
from email.message import EmailMessage
from fastapi import FastAPI, HTTPException, Request
from .engine import access_key, invoice_xml, sign_xml, send_sri, authorize_sri, ride_pdf

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


def validate(issue):
    if issue['issuer_ruc'] != os.environ['SRI_ISSUER_RUC']:
        raise ValueError('SRI_CERTIFICATE_ISSUER_MISMATCH')
    if issue['environment'] not in ('pruebas', 'produccion'):
        raise ValueError('SRI_ENVIRONMENT_INVALID')
    if issue['environment'] == 'produccion' and os.getenv('SRI_PRODUCTION_ENABLED') != 'true':
        raise ValueError('SRI_PRODUCTION_NOT_ENABLED')


def notify(issue, xml, pdf):
    email = issue['snapshot'].get('customer_email')
    if not email:
        raise ValueError('SRI_CUSTOMER_EMAIL_MISSING')
    msg = EmailMessage()
    msg['Subject'] = 'Factura electronica ' + issue['establishment'] + '-' + issue['emission_point'] + '-' + issue['sequential']
    msg['From'] = os.environ['SRI_SMTP_FROM']
    msg['To'] = email
    msg.set_content('Adjuntamos el comprobante electronico autorizado por el SRI y su RIDE.')
    msg.add_attachment(xml, maintype='application', subtype='xml', filename=access_key(issue) + '.xml')
    msg.add_attachment(pdf, maintype='application', subtype='pdf', filename=access_key(issue) + '.pdf')
    with smtplib.SMTP_SSL(os.environ['SRI_SMTP_HOST'], int(os.getenv('SRI_SMTP_PORT', '465')), timeout=20) as smtp:
        smtp.login(os.environ['SRI_SMTP_USER'], os.environ['SRI_SMTP_PASSWORD'])
        smtp.send_message(msg)


@app.post('/execute')
async def execute(request: Request):
    body = await request.body()
    expected = hmac.new(os.environ['SRI_WORKER_SECRET'].encode(), body, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(request.headers.get('x-sri-signature', ''), expected):
        raise HTTPException(401, 'UNAUTHORIZED')
    try:
        data = await request.json()
        issue = data['issue']
        validate(issue)
        action = data['action']
        if action == 'sign':
            xml, key = invoice_xml(issue)
            if issue.get('access_key') and issue['access_key'] != key:
                raise ValueError('SRI_ACCESS_KEY_MISMATCH')
            p12 = base64.b64decode(os.environ['SRI_P12_BASE64'], validate=True)
            signed = sign_xml(xml, p12, os.environ['SRI_P12_PASSWORD'])
            return {'access_key': key, 'signed_xml': base64.b64encode(signed).decode()}
        if action == 'receive':
            if issue['access_key'] != access_key(issue):
                raise ValueError('SRI_ACCESS_KEY_MISMATCH')
            return send_sri(base64.b64decode(data['signed_xml'], validate=True), issue['access_key'], issue['environment'])
        if action == 'authorize':
            if issue['access_key'] != access_key(issue):
                raise ValueError('SRI_ACCESS_KEY_MISMATCH')
            response = authorize_sri(issue['access_key'], issue['environment'])
            if response['status'] == 'authorized':
                issue['authorization'] = response['authorization']
                response['ride_pdf'] = base64.b64encode(ride_pdf(issue)).decode()
                response['authorized_xml'] = base64.b64encode(response['authorized_xml'].encode()).decode()
            return response
        if action == 'notify':
            if issue['status'] != 'authorized' or issue['authorization'] != issue['access_key']:
                raise ValueError('SRI_NOT_AUTHORIZED')
            notify(issue, base64.b64decode(data['authorized_xml'], validate=True),
                   base64.b64decode(data['ride_pdf'], validate=True))
            return {'delivered': True}
        raise ValueError('UNKNOWN_ACTION')
    except (ValueError, KeyError) as exc:
        raise HTTPException(422, str(exc)) from exc
