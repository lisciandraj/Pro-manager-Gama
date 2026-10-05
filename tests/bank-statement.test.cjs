const {test}=require('node:test'),assert=require('node:assert/strict'),{parse,cents}=require('../src/domain/bank-statement.js');
test('bank statements retain quoted separators, multiline descriptions, references and both decimal conventions',()=>{
 const a=parse('\uFEFFFecha;Referencia;Descripción;Importe\r\n05/10/2026;0000123;"Abono; oficina\ncon ""comillas""";1.234,56');assert.equal(a.rows[0].amount,1234.56);assert.equal(a.rows[0].reference,'0000123');assert.equal(a.rows[0].description,'Abono; oficina\ncon "comillas"');assert.equal(a.errors.length,0);
 const b=parse('sep=,\nDate,Reference,Description,Amount\n2026-10-05,ABC,Payment,"1,234.56"');assert.equal(b.rows[0].amount,1234.56);assert.equal(cents('(25.50)'),-2550);
 const c=parse('Fecha;Fecha valor;Importe\n01/10/2026;05/10/2026;US$ 12.50');assert.equal(c.rows[0].value_date,'2026-10-05');assert.equal(c.rows[0].amount,12.5);
});
test('debits, credits and explicit direction give the correct sign',()=>{
 const a=parse('Extracto de cuenta\nFecha\tDocumento\tDetalle\tDébitos\tCréditos\n05/10/2026\t0001\tPago\t25,50\t\n05/10/2026\t0002\tCobro\t\t50,00');assert.deepEqual(a.rows.map(x=>x.amount),[-25.5,50]);
 const b=parse('Fecha;Valor;Tipo\n05/10/2026;10.00;D\n05/10/2026;20.00;C');assert.deepEqual(b.rows.map(x=>x.amount),[-10,20]);
});
test('bad rows remain visible, including impossible dates and ambiguous amounts',()=>{
 const a=parse('Fecha;Referencia;Descripción;Importe\n31/02/2026;1;Bad;15.00\n05/10/2026;2;Ambiguous;1.234\n05/10/2026;3;Good;10.00');assert.equal(a.rows.length,1);assert.deepEqual(a.errors.map(e=>e.line),[2,3]);assert.equal(a.total,3);
 assert.equal(parse('Fecha;Importe\n05/10/2026;1.234',{decimalSeparator:','}).rows[0].amount,1234);
 assert.equal(parse('Fecha;Importe\n05/10/2026;0.001',{decimalSeparator:'.'}).errors.length,1);
 assert.equal(parse('Fecha;Débito;Crédito\n05/10/2026;10;5').errors.length,1);
 assert.equal(parse('Fecha;Importe;Tipo\n05/10/2026;-10;C').errors.length,1);
 assert.equal(parse('Fecha;Importe\n05/10/2026;NaN').errors.length,1);
});
test('statements never truncate excess movements or accept damaged CSV',()=>{
 assert.throws(()=>parse('Fecha;Importe\n'+Array(1001).fill('05/10/2026;1').join('\n')),/1000/);assert.throws(()=>parse('Fecha;Importe\n05/10/2026;"1'),/CSV/);assert.throws(()=>parse('Fecha;Importe'),/no contiene/);
});
