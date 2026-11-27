"use client";

import { useState } from "react";

type CustomField = { label: string; value: string };

export default function DocumentCustomFields() {
  const [fields, setFields] = useState<CustomField[]>([]);
  const update = (index: number, key: keyof CustomField, value: string) => {
    setFields((current) => current.map((field, fieldIndex) => fieldIndex === index ? { ...field, [key]: value } : field));
  };
  const serialized = JSON.stringify(fields.map(({ label, value }) => ({ label, value })));
  return <section className="document-custom-fields" aria-label="Additional document fields">
    <input type="hidden" name="custom_fields" value={serialized}/>
    <div className="document-custom-heading"><div><b>Additional information</b><small>Optional reference details to show with this document.</small></div>
      <button type="button" className="finance-action-button" disabled={fields.length >= 20} onClick={() => setFields((current) => current.length < 20 ? [...current, { label: "", value: "" }] : current)}>+ Add field</button>
    </div>
    {fields.map((field, index) => <div className="document-custom-row" key={index}>
      <label>Field name<input maxLength={60} required value={field.label} onChange={(event) => update(index, "label", event.target.value)} placeholder="Campaign / PO reference"/></label>
      <label>Value<input maxLength={240} required value={field.value} onChange={(event) => update(index, "value", event.target.value)} placeholder="Enter the value"/></label>
      <button type="button" className="document-line-remove" aria-label={`Remove custom field ${index + 1}`} onClick={() => setFields((current) => current.filter((_, fieldIndex) => fieldIndex !== index))}>Remove</button>
    </div>)}
    {fields.length >= 20 && <small className="document-custom-limit">Maximum 20 additional fields.</small>}
  </section>;
}
