// server.js
const express = require('express');
const { createClient } = require('@supabase/supabase-js');
const cors = require('cors');
const axios = require('axios');
const nodemailer = require('nodemailer');

const app = express();
app.use(cors());
app.use(express.json());

// Supabase setup
const SUPABASE_URL = 'https://hrzroqrgkvzhomsosqzl.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhyenJvcXJna3Z6aG9tc29zcXpsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDE5MjQ0NDQsImV4cCI6MjA1NzUwMDQ0NH0.qBDNsN0DvMKZ8JBAmoh2DsN8WW74uj2hZZuG_-gxF4g';
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Nodemailer setup for notifications
const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {
        user: 'your-email@gmail.com', // Replace with your email
        pass: 'your-app-password' // Replace with your app password
    }
});

// Constants
const REPORT_THRESHOLD = 10; // Number of reports to schedule a group
const TIME_LIMIT_DAYS = 3; // Time limit for a group (in days)

// Helper function: Haversine distance calculation
function haversineDistance(lat1, lon1, lat2, lon2) {
    const R = 6371; // Earth's radius in km
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
              Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
              Math.sin(dLon/2) * Math.sin(dLon/2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    return R * c; // Distance in km
}

// 1. User Reports Waste
app.post('/report-waste', async (req, res) => {
    const { userid, latitude, longitude } = req.body;

    try {
        // Insert the report into publicofficialapprovals
        const reportid = `report_${Date.now()}`;
        const { error: reportError } = await supabase
            .from('publicofficialapprovals')
            .insert({
                reportid,
                userid,
                location: `POINT(${longitude} ${latitude})`,
                wastype: 'unknown', // Can be updated later
                status: 'Pending',
                datetime: new Date().toISOString()
            });

        if (reportError) throw reportError;

        // Check for an open group in the area (within 1km radius for simplicity)
        const { data: groups, error: groupError } = await supabase
            .from('waste_groups')
            .select('*')
            .eq('status', 'Open');

        if (groupError) throw groupError;

        let targetGroup = null;
        for (const group of groups) {
            const groupLocation = group.location;
            const [groupLon, groupLat] = groupLocation.match(/POINT\(([^ ]+) ([^ ]+)\)/).slice(1).map(Number);
            const distance = haversineDistance(latitude, longitude, groupLat, groupLon);
            if (distance <= 1) { // 1km radius
                targetGroup = group;
                break;
            }
        }

        if (targetGroup) {
            // Add report to existing group
            const { error: updateError } = await supabase
                .from('waste_groups')
                .update({
                    report_count: targetGroup.report_count + 1,
                    reports: [...targetGroup.reports, reportid]
                })
                .eq('groupid', targetGroup.groupid);
            
            if (updateError) throw updateError;
        } else {
            // Create a new group
            const groupid = `group_${Date.now()}`;
            const { error: newGroupError } = await supabase
                .from('waste_groups')
                .insert({
                    groupid,
                    location: `POINT(${longitude} ${latitude})`,
                    status: 'Open',
                    created_at: new Date().toISOString(),
                    report_count: 1,
                    reports: [reportid]
                });
            
            if (newGroupError) throw newGroupError;
        }

        res.status(200).json({ message: 'Report submitted successfully', reportid });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// 2. Group Logic: Periodically check groups
async function checkGroups() {
    try {
        const { data: groups, error } = await supabase
            .from('waste_groups')
            .select('*')
            .eq('status', 'Open');

        if (error) throw error;

        const now = new Date();
        for (const group of groups) {
            const createdAt = new Date(group.created_at);
            const daysSinceCreation = (now - createdAt) / (1000 * 60 * 60 * 24);

            if (group.report_count >= REPORT_THRESHOLD || daysSinceCreation >= TIME_LIMIT_DAYS) {
                // Mark group as Scheduled
                const { error: updateError } = await supabase
                    .from('waste_groups')
                    .update({
                        status: 'Scheduled',
                        scheduled_at: now.toISOString()
                    })
                    .eq('groupid', group.groupid);

                if (updateError) throw updateError;

                // Allocate worker and notify
                const worker = await allocateWorker(group);
                if (worker) {
                    await notifyUsers(group);
                    await notifyWorker(worker, group);
                }
            }
        }
    } catch (error) {
        console.error('Error in checkGroups:', error.message);
    }
}

// Run checkGroups every hour
setInterval(checkGroups, 60 * 60 * 1000);

// 3. Worker Allocation
async function allocateWorker(group) {
    try {
        // Fetch available workers
        const { data: workers, error } = await supabase
            .from('users')
            .select('*, taskrequests!taskrequests_assignedworkerid_fkey(status)')
            .eq('role', 'worker')
            .neq('status', 'Collecting');

        if (error) throw error;

        if (!workers.length) return null;

        // Extract group's central location
        const groupLocation = group.location;
        const [groupLon, groupLat] = groupLocation.match(/POINT\(([^ ]+) ([^ ]+)\)/).slice(1).map(Number);

        // Find nearest worker
        let nearestWorker = null;
        let minDistance = Infinity;

        for (const worker of workers) {
            const workerLocation = worker.location;
            if (!workerLocation) continue;
            const [workerLon, workerLat] = workerLocation.match(/POINT\(([^ ]+) ([^ ]+)\)/).slice(1).map(Number);
            const distance = haversineDistance(groupLat, groupLon, workerLat, workerLon);
            if (distance < minDistance) {
                minDistance = distance;
                nearestWorker = worker;
            }
        }

        if (!nearestWorker) return null;

        // Fetch all report locations in the group
        const { data: reports, error: reportError } = await supabase
            .from('publicofficialapprovals')
            .select('location')
            .in('reportid', group.reports);

        if (reportError) throw reportError;

        const coordinates = reports.map(report => {
            const [lon, lat] = report.location.match(/POINT\(([^ ]+) ([^ ]+)\)/).slice(1).map(Number);
            return [lon, lat];
        });

        // Add worker's location as the starting point
        const workerLocation = nearestWorker.location;
        const [workerLon, workerLat] = workerLocation.match(/POINT\(([^ ]+) ([^ ]+)\)/).slice(1).map(Number);
        coordinates.unshift([workerLon, workerLat]);

        // Optimize route using OpenRouteService
        const orsResponse = await axios.post('https://api.openrouteservice.org/v2/directions/driving-car/geojson', {
            coordinates,
            instructions: true
        }, {
            headers: {
                'Authorization': 'Bearer YOUR_OPENROUTESERVICE_API_KEY', // Replace with your API key
                'Content-Type': 'application/json'
            }
        });

        const route = orsResponse.data;

        // Create a task for the worker
        const { error: taskError } = await supabase
            .from('taskrequests')
            .insert({
                reportid: `task_${group.groupid}_${Date.now()}`,
                assignedworkerid: nearestWorker.userid,
                status: 'Collecting',
                progress: 'Assigned',
                starttime: new Date().toISOString(),
                route: route // Store the route in the database (optional)
            });

        if (taskError) throw taskError;

        // Update worker status
        await supabase
            .from('users')
            .update({ status: 'Collecting' })
            .eq('userid', nearestWorker.userid);

        return { ...nearestWorker, route };
    } catch (error) {
        console.error('Error in allocateWorker:', error.message);
        return null;
    }
}

// 4. Notifications
async function notifyUsers(group) {
    try {
        // Fetch users who submitted reports in this group
        const { data: reports, error } = await supabase
            .from('publicofficialapprovals')
            .select('userid')
            .in('reportid', group.reports);

        if (error) throw error;

        const userIds = reports.map(report => report.userid);
        const { data: users, error: userError } = await supabase
            .from('users')
            .select('email, name')
            .in('userid', userIds);

        if (userError) throw userError;

        // Send email to each user
        for (const user of users) {
            await transporter.sendMail({
                from: 'your-email@gmail.com',
                to: user.email,
                subject: 'Waste Collection Scheduled',
                text: `Dear ${user.name},\n\nYour waste collection has been scheduled. A worker will collect the waste soon.\n\nGroup ID: ${group.groupid}\n\nThank you!`
            });
        }
    } catch (error) {
        console.error('Error in notifyUsers:', error.message);
    }
}

async function notifyWorker(worker, group) {
    try {
        const { data: reports, error } = await supabase
            .from('publicofficialapprovals')
            .select('location')
            .in('reportid', group.reports);

        if (error) throw error;

        const locations = reports.map(report => {
            const [lon, lat] = report.location.match(/POINT\(([^ ]+) ([^ ]+)\)/).slice(1).map(Number);
            return { lat, lon };
        });

        await transporter.sendMail({
            from: 'your-email@gmail.com',
            to: worker.email,
            subject: 'New Waste Collection Task',
            text: `Dear ${worker.name},\n\nYou have been assigned a new waste collection task.\n\nGroup ID: ${group.groupid}\nLocations: ${JSON.stringify(locations)}\nRoute: ${JSON.stringify(worker.route)}\n\nPlease start the collection soon.`
        });
    } catch (error) {
        console.error('Error in notifyWorker:', error.message);
    }
}

// 5. Complete Collection
app.post('/complete-collection', async (req, res) => {
    const { groupid, workerid } = req.body;

    try {
        // Update group status to Collected
        const { error: groupError } = await supabase
            .from('waste_groups')
            .update({ status: 'Collected' })
            .eq('groupid', groupid);

        if (groupError) throw groupError;

        // Update task status
        const { error: taskError } = await supabase
            .from('taskrequests')
            .update({
                status: 'Not Collecting',
                endtime: new Date().toISOString()
            })
            .eq('assignedworkerid', workerid)
            .eq('status', 'Collecting');

        if (taskError) throw taskError;

        // Update worker status
        await supabase
            .from('users')
            .update({ status: 'Not Collecting' })
            .eq('userid', workerid);

        res.status(200).json({ message: 'Collection completed successfully' });
    } catch (error) {
        console.error('Error in completeCollection:', error.message);
        res.status(500).json({ error: error.message });
    }
});

app.listen(3000, () => {
    console.log('Server running!');
});