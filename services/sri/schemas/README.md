# SRI document schemas

Downloaded from the [official electronic invoicing downloads](https://www.sri.gob.ec/facturacion-electronica) on 4 October 2026. These exact XSDs validate the XML before it can reach a signing or emission endpoint. Runtime parsing does not download schemas.

| File | Official bundle ID | SHA-256 |
| --- | --- | --- |
| LiquidacionCompra_V1.1.0.xsd | ee386507-04f8-4a45-b9cd-6d4e4c6ac1e6 | 58c9cd96edf93d92ef6692cd028e689080257c9ba2941fe04fe1d426ebc4b5b6 |
| NotaCredito_V1.1.0.xsd | dfc944cd-5f18-4433-a626-3cc64cfc4549 | 379e9f270d71ab4578f130a736c9abe5eb1d7969375ecdef55d2973583ec5ab0 |
| GuiaRemision_V1.1.0.xsd | 642ba34d-82d0-49d8-9622-5946f8eda268 | 4777fd94b5f7b108da3db0dd3d2c71d1539ced221cba246ebeaa40fb17f3dee1 |
| ComprobanteRetencion_V2.0.0.xsd | 90950fca-73a7-4cfb-9c2d-3142b10435f2 | 1e006d6d16c791c8f5b23d1f3e006cd066ccba2bfb797a3cb9098bd09c793cb7 |

Each bundle is served by `/o/sri-portlet-biblioteca-alfresco-internet/descargar/<bundle-id>/` on the official SRI site. The unchanged XML signature schema is from [W3C XMLDSIG](https://www.w3.org/TR/2002/REC-xmldsig-core-20020212/xmldsig-core-schema.xsd), SHA-256 `35cf8197da812c85e40d57891b35c94187569ed474a2dac813ce5090dafcd35c`.

The trusted W3C schema uses internal entities. Only bundled schema parsing enables them. Uploaded and returned XML rejects DTDs and entities and uses a separate parser with network and entity resolution disabled.
