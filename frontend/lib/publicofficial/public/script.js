// Supabase configuration
const SUPABASE_URL = 'https://hrzroqrgkvzhomsosqzl.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhyenJvcXJna3Z6aG9tc29zcXpsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDE5MjQ0NDQsImV4cCI6MjA1NzUwMDQ0NH0.qBDNsN0DvMKZ8JBAmoh2DsN8WW74uj2hZZuG_-gxF4g';
const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
const RENDER_URL = 'https://waas-9pr6.onrender.com';

document.addEventListener('DOMContentLoaded', () => {
    // Clear localStorage for development testing (comment out in production)
    localStorage.clear();

    // Check for existing login session
    const loggedInUser = localStorage.getItem('loggedInUser');
    if (loggedInUser) {
        showMainContent();
        initializeApp();
    }

    // Login Form Submission
    const loginForm = document.getElementById('loginForm');
    loginForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const email = document.getElementById('email').value;
        const password = document.getElementById('password').value;
        const errorElement = document.getElementById('loginError');

        try {
            const { data: user, error } = await supabaseClient
                .from('users')
                .select('userid, email, role, password')
                .eq('email', email)
                .eq('role', 'official')
                .single();

            if (error) throw error;

            if (user) {
                const { data: isMatch, error: verifyError } = await supabaseClient
                    .rpc('verify_password', {
                        input_password: password,
                        stored_hash: user.password
                    });

                if (verifyError) throw verifyError;

                if (isMatch) {
                    localStorage.setItem('loggedInUser', JSON.stringify(user));
                    showMainContent();
                    initializeApp();
                } else {
                    errorElement.textContent = 'Invalid credentials or not an admin';
                }
            } else {
                errorElement.textContent = 'Invalid credentials or not an admin';
            }
        } catch (error) {
            errorElement.textContent = 'Login failed. Please try again.';
            console.error('Login error:', error);
        }
    });
});

function showMainContent() {
    document.getElementById('loginContainer').style.display = 'none';
    document.getElementById('mainContent').style.display = 'block';
}

function initializeApp() {
    showSection('report');
    fetchWorkers();

    // Generate Report Form Submission
    const reportForm = document.getElementById('reportForm');
    reportForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const month = document.getElementById('month').value;
        const reportid = document.getElementById('reportid').value;
        const resultDiv = document.getElementById('reportResult');
        
        try {
            const [year, monthNum] = month.split('-').map(Number);
            const startOfMonth = `${year}-${monthNum.toString().padStart(2, '0')}-01T00:00:00Z`;
            const lastDay = new Date(year, monthNum, 0).getDate();
            const endOfMonth = `${year}-${monthNum.toString().padStart(2, '0')}-${lastDay}T23:59:59Z`;

            let reportQuery = supabaseClient
                .from('garbagereports')
                .select(`
                    reportid,
                    userid,
                    wastetype,
                    comments,
                    datetime,
                    users!garbagereports_userid_fkey(name)
                `)
                .gte('datetime', startOfMonth)
                .lte('datetime', endOfMonth);

            if (reportid) {
                reportQuery = reportQuery.eq('reportid', parseInt(reportid));
            }

            const { data: reportData, error: reportError } = await reportQuery;
            if (reportError) throw reportError;

            if (!reportData || reportData.length === 0) {
                resultDiv.innerHTML = `No reports found${reportid ? ` with ID ${reportid}` : ''} for the month of ${new Date(year, monthNum - 1).toLocaleString('default', { month: 'long', year: 'numeric' })}`;
                return;
            }

            const { data: allTasks, error: taskError } = await supabaseClient
                .from('taskrequests')
                .select(`
                    taskid,
                    reportids,
                    assignedworkerid,
                    status,
                    users!taskrequests_assignedworkerid_fkey(name)
                `);

            if (taskError) throw taskError;

            const combinedData = [];

            allTasks.forEach(task => {
                const taskReportIds = Array.isArray(task.reportids) 
                    ? task.reportids.map(id => parseInt(id))
                    : [parseInt(task.reportids)];

                taskReportIds.forEach(reportId => {
                    const matchingReport = reportData.find(r => parseInt(r.reportid) === reportId);
                    if (matchingReport) {
                        combinedData.push({
                            taskid: task.taskid,
                            reportid: matchingReport.reportid,
                            reportedBy: matchingReport.users?.name || 'Unknown',
                            wastetype: matchingReport.wastetype || 'Not specified',
                            comments: matchingReport.comments || 'None',
                            reportDate: matchingReport.datetime ? new Date(matchingReport.datetime).toLocaleString() : 'N/A',
                            assignedWorkerName: task.users?.name || 'Not assigned',
                            status: task.status || 'Unknown'
                        });
                    }
                });
            });

            reportData.forEach(report => {
                const hasTask = allTasks.some(task => {
                    const taskReportIds = Array.isArray(task.reportids) 
                        ? task.reportids.map(id => parseInt(id))
                        : [parseInt(task.reportids)];
                    return taskReportIds.includes(parseInt(report.reportid));
                });

                if (!hasTask) {
                    combinedData.push({
                        reportid: report.reportid,
                        reportedBy: report.users?.name || 'Unknown',
                        wastetype: report.wastetype || 'Not specified',
                        comments: report.comments || 'None',
                        reportDate: report.datetime ? new Date(report.datetime).toLocaleString() : 'N/A',
                        status: 'Not assigned',
                        assignedWorkerName: 'Not assigned'
                    });
                }
            });

            combinedData.sort((a, b) => {
                const dateA = new Date(a.reportDate);
                const dateB = new Date(b.reportDate);
                return dateA - dateB;
            });

            resultDiv.innerHTML = combinedData.map(entry => `
                <div>
                    ${entry.taskid ? `<strong>Task ID:</strong> ${entry.taskid}<br>` : ''}
                    <strong>Report ID:</strong> ${entry.reportid}<br>
                    <strong>Reported by:</strong> ${entry.reportedBy}<br>
                    <strong>Waste Type:</strong> ${entry.wastetype}<br>
                    <strong>Attended By:</strong> ${entry.assignedWorkerName}<br>
                    <strong>Status:</strong> ${entry.status}<br>
                    <strong>Comments:</strong> ${entry.comments}<br>
                    <strong>Report Date:</strong> ${entry.reportDate}<br>
                </div><hr>
            `).join('');

            const excelData = combinedData.map(entry => ({
                'Task ID': entry.taskid || 'N/A',
                'Report ID': entry.reportid,
                'Reported by': entry.reportedBy,
                'Waste Type': entry.wastetype,
                'Attended By': entry.assignedWorkerName,
                'Status': entry.status,
                'Comments': entry.comments,
                'Report Date': entry.reportDate
            }));

            const worksheet = XLSX.utils.json_to_sheet(excelData);
            const workbook = XLSX.utils.book_new();
            XLSX.utils.book_append_sheet(workbook, worksheet, 'Reports');

            const monthName = new Date(year, monthNum - 1).toLocaleString('default', { month: 'long', year: 'numeric' });
            const fileName = `Reports_${monthName}${reportid ? `_ID_${reportid}` : ''}.xlsx`;
            XLSX.writeFile(workbook, fileName);

            resultDiv.innerHTML += `<p>Report generated and downloaded as ${fileName}</p>`;
        } catch (error) {
            resultDiv.innerHTML = `Error generating report: ${error.message}`;
        }
    });

    // Add Worker Form Submission
    const workerForm = document.getElementById('workerForm');
    workerForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        
        const randomNum = Math.floor(100 + Math.random() * 900);
        const generatedPassword = `Wor${randomNum}`;
        
        const worker = {
            userid: parseInt(document.getElementById('workerId').value),
            name: document.getElementById('workerName').value,
            email: document.getElementById('workerEmail').value,
            phone: document.getElementById('workerPhone').value,
            address: document.getElementById('workerAddress').value,
            role: 'worker',
            status: 'available'
        };

        try {
            const { data: hashData, error: hashError } = await supabaseClient
                .rpc('hash_password', { 
                    plain_password: generatedPassword 
                });
            
            if (hashError) throw hashError;

            const { error } = await supabaseClient
                .from('users')
                .insert([{ 
                    ...worker, 
                    password: hashData 
                }]);
            
            if (error) throw error;
            
            alert(`Worker added successfully!\nGenerated password: ${generatedPassword}\nThis password cannot be retrieved later, so please provide it to the worker now.`);
            
            workerForm.reset();
            await fetchWorkers();
        } catch (error) {
            alert(`Error adding worker: ${error.message}`);
        }
    });
}

function showSection(sectionId) {
    document.querySelectorAll('.section').forEach(section => {
        section.classList.remove('active');
    });
    document.getElementById(sectionId).classList.add('active');
}

async function fetchWorkers() {
    try {
        const { data, error } = await supabaseClient
            .from('users')
            .select('*, taskrequests!taskrequests_assignedworkerid_fkey(status)')
            .eq('role', 'worker');
        
        if (error) throw error;
        updateWorkerTable(data);
    } catch (error) {
        alert(`Error fetching workers: ${error.message}`);
    }
}

function updateWorkerTable(workers) {
    const tbody = document.getElementById('workerTableBody');
    tbody.innerHTML = '';
    
    workers.forEach((worker) => {
        const taskStatus = worker.taskrequests && worker.taskrequests.length > 0 
            ? worker.taskrequests[0].status 
            : 'Not Collecting';
        
        const row = document.createElement('tr');
        row.innerHTML = `
            <td>${worker.userid}</td>
            <td>${worker.name}</td>
            <td>${worker.email}</td>
            <td>${taskStatus}</td>
        `;
        tbody.appendChild(row);
    });
}

async function toggleStatus(workerId, currentStatus) {
    const newStatus = currentStatus === 'Collecting' ? 'Not Collecting' : 'Collecting';
    try {
        const { data: existingTasks, error: fetchError } = await supabaseClient
            .from('taskrequests')
            .select('reportids')
            .eq('assignedworkerid', parseInt(workerId))
            .eq('status', 'Collecting');
        
        if (fetchError) throw fetchError;

        if (existingTasks.length > 0) {
            const response = await fetch(`${RENDER_URL}/complete-collection`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ 
                    groupid: existingTasks[0].reportids, 
                    workerid: parseInt(workerId) 
                })
            });

            if (!response.ok) {
                const data = await response.json();
                throw new Error(data.error);
            }

            const { error } = await supabaseClient
                .from('taskrequests')
                .update({
                    status: newStatus,
                    endtime: newStatus === 'Not Collecting' ? new Date().toISOString() : null
                })
                .eq('assignedworkerid', parseInt(workerId))
                .eq('status', 'Collecting');
            
            if (error) throw error;
        } else if (newStatus === 'Collecting') {
            const { error } = await supabaseClient
                .from('taskrequests')
                .insert([{
                    taskid: parseInt(Math.random() * 1000),
                    reportids: parseInt(Math.random() * 100),
                    assignedworkerid: parseInt(workerId),
                    status: newStatus,
                    starttime: new Date().toISOString()
                }]);
            
            if (error) throw error;
        }

        await fetchWorkers();
    } catch (error) {
        alert(`Error updating status: ${error.message}`);
    }
}

function logout() {
    localStorage.removeItem('loggedInUser');
    document.getElementById('mainContent').style.display = 'none';
    document.getElementById('loginContainer').style.display = 'flex';
}