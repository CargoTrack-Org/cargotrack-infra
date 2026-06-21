'use strict';

const { DynamoDBClient, PutItemCommand } = require('@aws-sdk/client-dynamodb');

const dynamodb = new DynamoDBClient({ region: process.env.AWS_REGION_NAME });

exports.handler = async (event) => {
  for (const record of event.Records) {
    // ── 1. Parse the SQS message body (EventBridge envelope) ──────────────
    let body;
    try {
      body = JSON.parse(record.body);
    } catch {
      console.error('[document-processor] Failed to parse SQS message body:', record.body);
      throw new Error('Failed to parse SQS message body');
    }

    console.log('[document-processor] Processing event:', JSON.stringify(body, null, 2));
    console.log('[document-processor] detail-type:', body['detail-type']);
    console.log('[document-processor] detail:', JSON.stringify(body.detail, null, 2));

    // ── 2. Extract fields from the EventBridge event ───────────────────────
    const detail    = body.detail    || {};
    const eventType = body['detail-type'] || 'Unknown';
    const timestamp = body.time       || new Date().toISOString();

    const shipmentId   = detail.shipmentId;
    const documentId   = detail.documentId   || '';
    const documentType = detail.documentType || '';
    const fileName     = detail.fileName     || '';
    const uploadedBy   = detail.uploadedBy   || '';

    // ── 3. Validate required fields ────────────────────────────────────────
    if (!shipmentId) {
      console.error('[document-processor] Missing required field: shipmentId. detail:', JSON.stringify(detail));
      throw new Error('Missing required field: shipmentId');
    }

    // ── 4. Write audit record to DynamoDB ──────────────────────────────────
    const item = {
      shipmentId:   { S: shipmentId },
      timestamp:    { S: timestamp },
      eventType:    { S: eventType },
      documentId:   { S: documentId },
      documentType: { S: documentType },
      fileName:     { S: fileName },
      uploadedBy:   { S: uploadedBy },
    };

    try {
      await dynamodb.send(new PutItemCommand({
        TableName: process.env.AUDIT_TABLE_NAME,
        Item:      item,
      }));

      console.log(
        `[document-processor] Audit record written — shipmentId: ${shipmentId},` +
        ` eventType: ${eventType}, timestamp: ${timestamp}`
      );
    } catch (err) {
      // Re-throw so the SQS event source mapping retries and eventually sends
      // the message to the DLQ — preserving at-least-once delivery guarantees.
      console.error('[document-processor] Failed to write audit record to DynamoDB:', err);
      throw err;
    }
  }
};
