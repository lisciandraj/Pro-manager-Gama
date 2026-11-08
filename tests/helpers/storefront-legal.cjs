// Fictional information for isolated commercial-intake fixtures only.
const legalInformation={
 legal_name:'Fictional fixture company',legal_tax_id:'1799999999001',
 legal_address:'Fictional fixture street, Quito',privacy_email:'privacy@example.invalid',
 privacy_retention:'Fixture schedule: requests retained only for the stated test purpose.',
 privacy_recipients:'Fixture processors and authorized personnel; no real data is transferred.',
 privacy_rights_process:'Contact the fixture privacy team to exercise applicable rights.'
};
async function configureLegalInformation(db){
 await db.query('update private.website_public_settings set config=config||$1::jsonb where id',[JSON.stringify(legalInformation)]);
}
module.exports={legalInformation,configureLegalInformation};
