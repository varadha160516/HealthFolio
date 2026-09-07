import { Router } from 'express';
import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { requireAuth } from '../middleware/auth.js';
import { assertFamilyAccess } from './family.js';
import { answerChatQuestion, ChatTurn } from '../pipeline/chatAssistant.js';

export const chatRouter = Router();

chatRouter.get('/members/:id/chat', requireAuth, (req, res) => {
  const memberId = req.params.id;
  if (!assertFamilyAccess(req, res, memberId)) return;
  const rows = db
    .prepare('SELECT id, role, content, created_at FROM chat_messages WHERE member_id = ? ORDER BY created_at ASC')
    .all(memberId);
  res.json(rows);
});

chatRouter.post('/members/:id/chat', requireAuth, async (req, res) => {
  const memberId = req.params.id;
  if (!assertFamilyAccess(req, res, memberId)) return;
  const message = (req.body?.message as string | undefined)?.trim();
  if (!message) return res.status(400).json({ error: 'message is required' });

  const session = req.session!;
  const priorHistory = db
    .prepare('SELECT role, content FROM chat_messages WHERE member_id = ? ORDER BY created_at ASC')
    .all(memberId) as unknown as ChatTurn[];

  const userMessageId = uuid();
  const userCreatedAt = now();
  db.prepare('INSERT INTO chat_messages (id, member_id, asked_by_user_id, role, content, created_at) VALUES (?, ?, ?, ?, ?, ?)').run(
    userMessageId,
    memberId,
    session.userId,
    'user',
    message,
    userCreatedAt
  );

  try {
    const reply = await answerChatQuestion(memberId, priorHistory, message);
    const assistantMessageId = uuid();
    const assistantCreatedAt = now();
    db.prepare('INSERT INTO chat_messages (id, member_id, asked_by_user_id, role, content, created_at) VALUES (?, ?, ?, ?, ?, ?)').run(
      assistantMessageId,
      memberId,
      session.userId,
      'assistant',
      reply,
      assistantCreatedAt
    );
    res.status(201).json({
      userMessage: { id: userMessageId, role: 'user', content: message, created_at: userCreatedAt },
      assistantMessage: { id: assistantMessageId, role: 'assistant', content: reply, created_at: assistantCreatedAt },
    });
  } catch (err) {
    // Roll the user's question back out rather than leaving an unanswered message stranded in
    // the conversation history — the client should treat this as "send failed", not "sent".
    db.prepare('DELETE FROM chat_messages WHERE id = ?').run(userMessageId);
    console.error(err);
    res.status(502).json({ error: 'The health assistant is unavailable right now — please try again.' });
  }
});

chatRouter.delete('/members/:id/chat', requireAuth, (req, res) => {
  const memberId = req.params.id;
  if (!assertFamilyAccess(req, res, memberId)) return;
  db.prepare('DELETE FROM chat_messages WHERE member_id = ?').run(memberId);
  res.status(204).end();
});
