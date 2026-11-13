import test from 'node:test';
import assert from 'node:assert/strict';
import { reportHTML, validateReport } from '../reports/template.mjs';
for (const kind of ['shear-centre', 'buckling', 'arch']) {
  test(`${kind} report includes escaped inputs, units and checks`, () => {
    const r = {status:'completed',analysisType:kind,analysisId:'test',inputSummary:{type:kind,projectName:'<script>bad()</script>',length:3,E:200},computationMetadata:{},solverMethod:'Julia',results:{metrics:[{label:'Result',value:1,unit:'kN'}],tables:[],checks:[{label:'Residual',value:0,unit:'N'}],notes:[]},warnings:[],plots:[{label:'Curve',unit:'N/mm',x:[0,1],values:[0,1],color:'#123456',xLabel:'Distance along wall (mm)',xUnit:'mm'}]};
    validateReport(r);
    const html = reportHTML(r);
    assert.ok(html.includes('&lt;script&gt;bad()&lt;/script&gt;'));
    assert.ok(html.includes('Distance along wall (mm)'));
    assert.ok(html.includes('GPa'));
    assert.ok(html.includes('Residual'));
    assert.ok(!html.includes('All implemented per-run checks passed'));
    assert.throws(() => validateReport({...r,status:'failed'}));
    assert.throws(() => validateReport({...r,results:{...r.results,metrics:[]}}));
  });
}
