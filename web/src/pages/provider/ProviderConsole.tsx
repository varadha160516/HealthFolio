import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../../api/client';

export function ProviderConsole() {
  const [appointments, setAppointments] = useState<any[]>([]);

  function load() {
    api.getAppointments().then(setAppointments);
  }
  useEffect(() => {
    load();
    const t = setInterval(load, 4000); // live status poll (Section 7.1/8.1 step 3)
    return () => clearInterval(t);
  }, []);

  async function checkIn(id: string) {
    await api.checkIn(id);
    load();
  }

  return (
    <div>
      <h2>Today's appointments</h2>
      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Patient</th>
              <th>When</th>
              <th>Status</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {appointments.map((a) => (
              <tr key={a.id}>
                <td>{a.member?.name}</td>
                <td className="muted">{new Date(a.datetime).toLocaleString()}</td>
                <td>
                  <span className={`pill status-${a.status}`}>{a.status.replace(/_/g, ' ')}</span>
                </td>
                <td>
                  <div className="flex gap">
                    {a.status === 'scheduled' && <button onClick={() => checkIn(a.id)}>Check in</button>}
                    <Link to={`/console/${a.id}`}>
                      <button>Open</button>
                    </Link>
                  </div>
                </td>
              </tr>
            ))}
            {appointments.length === 0 && (
              <tr>
                <td colSpan={4} className="muted">
                  No appointments yet.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
