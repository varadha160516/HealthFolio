import express from 'express';
import cors from 'cors';
import { authRouter } from './routes/auth.js';
import { familyRouter } from './routes/family.js';
import { documentsRouter } from './routes/documents.js';
import { parametersRouter } from './routes/parameters.js';
import { adminRouter } from './routes/admin.js';
import { appointmentsRouter } from './routes/appointments.js';
import { auditRouter } from './routes/audit.js';
import { prescriptionsRouter } from './routes/prescriptions.js';
import { chatRouter } from './routes/chat.js';
import { symptomsRouter } from './routes/symptoms.js';
import { medicationsRouter } from './routes/medications.js';
import { labTestsRouter } from './routes/labTests.js';
import { translateRouter } from './routes/translate.js';
import { doctorAppRouter } from './routes/doctorApp.js';
import { invoicesRouter } from './routes/invoices.js';
import { pharmacyOrdersRouter } from './routes/pharmacyOrders.js';
import { extractionModeLabel } from './pipeline/extract.js';

export function buildApp() {
  const app = express();
  app.use(cors());
  app.use(express.json({ limit: '2mb' }));

  app.get('/api/health', (_req, res) => res.json({ ok: true, extractionMode: extractionModeLabel() }));

  app.use('/api', authRouter);
  app.use('/api', familyRouter);
  app.use('/api', documentsRouter);
  app.use('/api', parametersRouter);
  app.use('/api', adminRouter);
  app.use('/api', appointmentsRouter);
  app.use('/api', auditRouter);
  app.use('/api', prescriptionsRouter);
  app.use('/api', chatRouter);
  app.use('/api', symptomsRouter);
  app.use('/api', medicationsRouter);
  app.use('/api', labTestsRouter);
  app.use('/api', translateRouter);
  app.use('/api', doctorAppRouter);
  app.use('/api', invoicesRouter);
  app.use('/api', pharmacyOrdersRouter);

  app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  });

  return app;
}
