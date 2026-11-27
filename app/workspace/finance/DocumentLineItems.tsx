"use client";

import { useState } from "react";

type LineItem = {
  group_name: string;
  description: string;
  quantity: string;
  unit: string;
  unit_price: string;
};

const emptyLine = (group_name = ""): LineItem => ({
  group_name,
  description: "",
  quantity: "1",
  unit: "unit",
  unit_price: "",
});

export default function DocumentLineItems() {
  const [items, setItems] = useState<LineItem[]>([emptyLine()]);
  const update = (index: number, key: keyof LineItem, value: string) => {
    setItems((current) => current.map((item, itemIndex) => itemIndex === index ? { ...item, [key]: value } : item));
  };
  const addLine = () => setItems((current) => current.length < 50 ? [...current, emptyLine()] : current);
  const addGroup = () => setItems((current) => current.length < 50 ? [...current, emptyLine(`Group ${current.length + 1}`)] : current);
  const removeLine = (index: number) => setItems((current) => current.length > 1 ? current.filter((_, itemIndex) => itemIndex !== index) : current);

  const serializedItems = JSON.stringify(items.map((item) => ({
    group_name: item.group_name,
    description: item.description,
    quantity: Number(item.quantity),
    unit: item.unit,
    unit_price: item.unit_price === "" ? "" : Number(item.unit_price),
  })));

  return <section className="document-line-editor" aria-label="Document line items">
    <input type="hidden" name="line_items" value={serializedItems}/>
    <div className="document-lines-heading"><div><b>Services & deliverables</b><small>Add separate lines and group them by project phase or service.</small></div><span>{items.length} {items.length === 1 ? "line" : "lines"}</span></div>
    <div className="document-line-list">
      {items.map((item, index) => <fieldset className="document-line-row" key={index}>
        <legend>Line {index + 1}</legend>
        <div className="document-line-fields">
          <label>Group (optional)<input maxLength={80} value={item.group_name} onChange={(event) => update(index, "group_name", event.target.value)} placeholder="Strategy & planning"/></label>
          <label className="document-line-description">Service / deliverable<input maxLength={240} required value={item.description} onChange={(event) => update(index, "description", event.target.value)} placeholder="Monthly social media management"/></label>
          <label>Quantity<input type="number" min="0.01" max="9999999999" step="0.01" required value={item.quantity} onChange={(event) => update(index, "quantity", event.target.value)}/></label>
          <label>Unit<input maxLength={30} required value={item.unit} onChange={(event) => update(index, "unit", event.target.value)} placeholder="hours, posts, unit"/></label>
          <label>Rate<input type="number" min="0" max="999999999999.99" step="0.01" required value={item.unit_price} onChange={(event) => update(index, "unit_price", event.target.value)} placeholder="0.00"/></label>
          <button className="document-line-remove" type="button" aria-label={`Remove line ${index + 1}`} disabled={items.length === 1} onClick={() => removeLine(index)}>Remove</button>
        </div>
      </fieldset>)}
    </div>
    <div className="document-line-buttons"><button type="button" className="finance-action-button" disabled={items.length >= 50} onClick={addLine}>+ Add line</button><button type="button" className="finance-action-button" disabled={items.length >= 50} onClick={addGroup}>+ Add group</button>{items.length >= 50 && <small>Maximum 50 lines per document.</small>}</div>
  </section>;
}
